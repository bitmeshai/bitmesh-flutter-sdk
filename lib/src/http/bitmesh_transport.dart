import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../bitmesh_file.dart';
import '../bitmesh_options.dart';
import '../exceptions.dart';
import '../logging.dart';
import 'server_sent_events.dart';

/// A completed HTTP exchange.
class BitmeshResponse {
  BitmeshResponse({
    required this.statusCode,
    required this.bodyBytes,
    required this.headers,
  });

  final int statusCode;
  final Uint8List bodyBytes;

  /// Response headers, names in lower case.
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// `X-Bitmesh-Request-Id`, when the API sent one (proxy and streamed chat).
  String? get requestId => headers['x-bitmesh-request-id'];

  late final String body = _decodeBody();

  /// The body parsed as a JSON object.
  Map<String, dynamic> json() => BitmeshTransport.decodeJsonObject(body);

  String _decodeBody() {
    try {
      return utf8.decode(bodyBytes);
    } on FormatException {
      return utf8.decode(bodyBytes, allowMalformed: true);
    }
  }
}

/// Sends and retries HTTP requests against the Bitmesh API v2.
///
/// This is the only layer that talks to `package:http`. Each attempt asks for
/// a fresh App Check token, so a retry never carries an expired one.
class BitmeshTransport {
  BitmeshTransport({
    required String apiKey,
    required this.options,
    http.Client? httpClient,
  })  : _apiKey = apiKey,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null {
    final parsed = Uri.tryParse(options.baseUrl);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw BitmeshConfigurationException(
        'Invalid baseUrl "${options.baseUrl}". Expected an absolute URL such as '
        '"https://api.bitmesh.ai".',
      );
    }
  }

  /// The API version every authenticated path is served under.
  static const String apiVersion = 'v2';

  /// Header carrying the Firebase App Check token on mobile keys.
  static const String appCheckHeader = 'X-Firebase-AppCheck';

  /// Header carrying a debug token in place of App Check while testing.
  static const String debugTokenHeader = 'X-Bitmesh-Debug-Token';

  final String _apiKey;
  final BitmeshOptions options;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  BitmeshLogger? get _logger => options.logger;

  /// `POST` with a JSON body, returning a decoded JSON object.
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await send('POST', path, body: jsonEncode(payload));
    return response.json();
  }

  /// `GET`, returning a decoded JSON object.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final response = await send('GET', path, query: query);
    return response.json();
  }

  /// `multipart/form-data` `POST`, returning a decoded JSON object.
  ///
  /// Nested maps are flattened to `parent[child]` field names and lists to
  /// `name[0]`, `name[1]`. Booleans are sent as `"1"` / `"0"`, numbers as
  /// text, and `null`s are left out.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    Map<String, dynamic> fields = const {},
    List<BitmeshFile> files = const [],
  }) async {
    for (final file in files) {
      file.validate();
    }

    final uri = apiUri(path);
    final flatFields = flattenFields(multipartWireFields(fields));

    final exchange = await _send(
      method: 'POST',
      uri: uri,
      idempotent: false,
      buildRequest: () async {
        final request = http.MultipartRequest('POST', uri)
          ..headers.addAll({..._baseHeaders(), ...await _authHeaders()});
        flatFields.forEach((key, value) {
          request.fields[key] = value?.toString() ?? '';
        });
        for (final file in files) {
          // Rebuilt on every attempt: multipart bodies are single-use streams.
          request.files.add(await file.toMultipartFile());
        }
        return request;
      },
    );

    return exchange.response.json();
  }

  /// An authenticated request to `{baseUrl}/v2/{path}`, returning the whole
  /// response. Non-2xx answers throw a [BitmeshApiException].
  ///
  /// [body] is sent as is, as `application/json` unless [headers] say
  /// otherwise. Only `GET` is retried on server errors.
  Future<BitmeshResponse> send(
    String method,
    String path, {
    String? body,
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = apiUri(path, query: query);
    final exchange = await _send(
      method: method,
      uri: uri,
      idempotent: method == 'GET',
      buildRequest: () => _request(method, uri, body, headers),
    );
    return exchange.response;
  }

  /// An authenticated request whose reply is a stream of server-sent events.
  ///
  /// Retries and errors are handled as for [send] until the response starts;
  /// after that, events are passed on as they arrive. Cancelling the
  /// subscription closes the connection.
  Stream<ServerSentEvent> stream(
    String method,
    String path, {
    String? body,
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    void Function(BitmeshResponse head)? onResponse,
  }) async* {
    final uri = apiUri(path, query: query);
    final exchange = await _send(
      method: method,
      uri: uri,
      idempotent: false,
      stream: true,
      buildRequest: () => _request(
        method,
        uri,
        body,
        {'Accept': 'text/event-stream', ...headers},
      ),
    );
    onResponse?.call(exchange.response);

    try {
      yield* exchange.body!.transform(const ServerSentEventDecoder());
    } on http.ClientException catch (e, s) {
      throw _networkFailure(method, uri, e, s);
    } catch (e, s) {
      if (_isNetworkError(e)) throw _networkFailure(method, uri, e, s);
      rethrow;
    }
  }

  /// Unsigned `GET` for public result paths (`/imgrslt/...`, tool outputs),
  /// relative to the base URL, not to `/v2`.
  Future<BitmeshResponse> getPublic(String path) =>
      getPublicUri(_uri(path));

  /// Unauthenticated `GET` of an absolute URL, such as a result link that a
  /// tool's provider hosts itself.
  Future<BitmeshResponse> getPublicUri(Uri uri) async {
    final exchange = await _send(
      method: 'GET',
      uri: uri,
      idempotent: true,
      buildRequest: () async => http.Request('GET', uri)
        ..headers.addAll({
          ...options.defaultHeaders,
          if (options.userAgent != null) 'User-Agent': options.userAgent!,
        }),
    );
    return exchange.response;
  }

  /// The headers of an authenticated request: defaults, `User-Agent`, the
  /// key and the App Check or debug token. For connections the transport
  /// doesn't send itself, such as a real-time transcription WebSocket.
  Future<Map<String, String>> authenticatedHeaders() async =>
      {..._baseHeaders(), ...await _authHeaders()};

  /// `{baseUrl}/v2/{path}`.
  Uri apiUri(String path, {Map<String, String> query = const {}}) =>
      _uri('$apiVersion/${path.replaceAll(RegExp(r'^/+'), '')}', query: query);

  Uri _uri(String path, {Map<String, String> query = const {}}) {
    final base = options.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final relative = path.replaceAll(RegExp(r'^/+'), '');
    final uri = Uri.parse('$base/$relative');
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  /// The fields as they go over the wire: booleans become `"1"` or `"0"`,
  /// numbers their string form, and `null`s and empty collections are left
  /// out. Nested maps and lists are kept for [flattenFields].
  static Map<String, dynamic> multipartWireFields(Map<String, dynamic> fields) {
    final wire = _wireValue(fields);
    return wire is Map<String, dynamic> ? wire : <String, dynamic>{};
  }

  static Object? _wireValue(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? '1' : '0';
    if (value is String) return value;
    if (value is num) return value.toString();
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((key, item) {
        final wire = _wireValue(item);
        if (wire != null) out[key.toString()] = wire;
      });
      return out.isEmpty ? null : out;
    }
    if (value is Iterable) {
      final out = value.map(_wireValue).whereType<Object>().toList();
      return out.isEmpty ? null : out;
    }
    return value.toString();
  }

  /// Flattens nested maps into `parent[child]` multipart field names.
  static Map<String, dynamic> flattenFields(
    Map<String, dynamic> fields, [
    String prefix = '',
  ]) {
    final result = <String, dynamic>{};
    for (final entry in fields.entries) {
      final name = prefix.isEmpty ? entry.key : '$prefix[${entry.key}]';
      final value = entry.value;
      if (value is Map) {
        result.addAll(flattenFields(value.cast<String, dynamic>(), name));
      } else if (value is Iterable) {
        var index = 0;
        for (final item in value) {
          final itemName = '$name[${index++}]';
          if (item is Map) {
            result.addAll(flattenFields(item.cast<String, dynamic>(), itemName));
          } else {
            result[itemName] = item;
          }
        }
      } else {
        result[name] = value;
      }
    }
    return result;
  }

  /// Parses [body] as a JSON object, or throws [BitmeshSerializationException].
  static Map<String, dynamic> decodeJsonObject(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw BitmeshSerializationException(
        'Bitmesh API returned a body that is not valid JSON: ${e.message}',
        body: body,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw BitmeshSerializationException(
        'Expected a JSON object from the Bitmesh API but got '
        '${decoded.runtimeType}.',
        body: body,
      );
    }
    return decoded;
  }

  /// Releases the underlying connection pool.
  ///
  /// Only closes the client when the transport created it; an injected
  /// [http.Client] stays under the caller's ownership.
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  Future<http.BaseRequest> _request(
    String method,
    Uri uri,
    String? body,
    Map<String, String> extra,
  ) async {
    final request = http.Request(method, uri);
    request.headers.addAll({
      ..._baseHeaders(),
      if (body != null) 'Content-Type': 'application/json',
      ...extra,
      ...await _authHeaders(),
    });
    if (body != null) request.body = body;
    return request;
  }

  Map<String, String> _baseHeaders() => {
        'Accept': 'application/json',
        ...options.defaultHeaders,
        if (options.userAgent != null) 'User-Agent': options.userAgent!,
      };

  /// The key and the App Check or debug token. Applied last, so neither
  /// default headers nor per-call headers can replace them.
  Future<Map<String, String>> _authHeaders() async {
    final debugToken = options.debugToken;
    final appCheckToken = debugToken == null ? await _appCheckToken() : null;
    return {
      'Authorization': 'Bearer $_apiKey',
      if (debugToken != null) debugTokenHeader: debugToken,
      if (appCheckToken != null) appCheckHeader: appCheckToken,
    };
  }

  /// The App Check token for one attempt, or `null` when no provider is set.
  ///
  /// A provider that fails stops the request here: without a token a mobile
  /// key is refused anyway.
  Future<String?> _appCheckToken() async {
    final provider = options.appCheckTokenProvider;
    if (provider == null) return null;

    String? token;
    try {
      token = await provider();
    } catch (e, s) {
      _log(BitmeshLogLevel.error, 'App Check token provider failed',
          error: e, stackTrace: s);
      throw BitmeshAppCheckTokenException(
        'Could not get a Firebase App Check token. Check that App Check is '
        'set up for this app in the Firebase console.',
        cause: e,
      );
    }

    if (token == null || token.trim().isEmpty) {
      _log(BitmeshLogLevel.error, 'App Check token provider returned no token');
      throw const BitmeshAppCheckTokenException(
        'The App Check token provider returned no token. Check that App '
        'Check is activated before the first request.',
      );
    }
    return token;
  }

  Future<_Exchange> _send({
    required String method,
    required Uri uri,
    required bool idempotent,
    required Future<http.BaseRequest> Function() buildRequest,
    bool stream = false,
  }) async {
    final policy = options.retryPolicy;
    var attempt = 0;

    while (true) {
      attempt++;
      final isLastAttempt = attempt >= policy.maxAttempts;

      try {
        final exchange = await _attempt(method, uri, buildRequest, stream);
        final response = exchange.response;

        if (response.isSuccess) {
          _log(BitmeshLogLevel.debug,
              '$method ${uri.path} -> ${response.statusCode}');
          return exchange;
        }

        final error = BitmeshApiException.fromResponse(
          response.statusCode,
          response.body,
          headers: response.headers,
        );

        if (isLastAttempt ||
            !policy.shouldRetryStatus(response.statusCode,
                idempotent: idempotent)) {
          _log(BitmeshLogLevel.error,
              '$method ${uri.path} failed: ${error.statusCode} ${error.message}');
          throw error;
        }

        await _backoff(attempt, method, uri, error.retryAfter,
            '${error.statusCode} ${error.message}');
      } on BitmeshException catch (e) {
        if (e is BitmeshApiException || e is BitmeshArgumentException) rethrow;
        if (isLastAttempt ||
            !policy.retryNetworkErrors ||
            !(e is BitmeshNetworkException || e is BitmeshTimeoutException)) {
          rethrow;
        }
        await _backoff(attempt, method, uri, null, e.message);
      }
    }
  }

  Future<_Exchange> _attempt(
    String method,
    Uri uri,
    Future<http.BaseRequest> Function() buildRequest,
    bool stream,
  ) async {
    try {
      return await _exchange(buildRequest, stream).timeout(options.timeout);
    } on TimeoutException {
      throw BitmeshTimeoutException(
        options.timeout,
        detail: '$method ${uri.path} timed out.',
      );
    } on http.ClientException catch (e, s) {
      throw _networkFailure(method, uri, e, s);
    } on BitmeshException {
      rethrow;
    } catch (e, s) {
      if (_isNetworkError(e)) throw _networkFailure(method, uri, e, s);
      rethrow;
    }
  }

  Future<_Exchange> _exchange(
    Future<http.BaseRequest> Function() buildRequest,
    bool stream,
  ) async {
    final request = await buildRequest();
    final streamed = await _httpClient.send(request);
    final success = streamed.statusCode >= 200 && streamed.statusCode < 300;

    // A successful stream is handed on unread; anything else is read whole.
    final body = stream && success ? streamed.stream : null;
    final bytes = body == null ? await streamed.stream.toBytes() : Uint8List(0);

    return _Exchange(
      BitmeshResponse(
        statusCode: streamed.statusCode,
        bodyBytes: bytes,
        headers: streamed.headers,
      ),
      body,
    );
  }

  BitmeshNetworkException _networkFailure(
    String method,
    Uri uri,
    Object error,
    StackTrace stackTrace,
  ) {
    _log(
      BitmeshLogLevel.warning,
      '$method ${uri.path} network failure',
      error: error,
      stackTrace: stackTrace,
    );
    return BitmeshNetworkException(
      'Could not reach the Bitmesh API at ${uri.host}. '
      'Check connectivity and try again.',
      cause: error,
    );
  }

  Future<void> _backoff(
    int attempt,
    String method,
    Uri uri,
    Duration? retryAfter,
    String reason,
  ) async {
    final delay =
        options.retryPolicy.delayFor(attempt, retryAfter: retryAfter);
    _log(
      BitmeshLogLevel.warning,
      'Retrying $method ${uri.path} in ${delay.inMilliseconds}ms '
      '(attempt ${attempt + 1}/${options.retryPolicy.maxAttempts}): $reason',
    );
    await Future<void>.delayed(delay);
  }

  void _log(
    BitmeshLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger?.log(level, message, error: error, stackTrace: stackTrace);
  }

  // Recognises `dart:io` connectivity errors by name, so the package does not
  // have to import `dart:io` and stays web-compatible.
  static const Set<String> _networkErrorTypes = {
    'SocketException',
    'HandshakeException',
    'TlsException',
    'HttpException',
    'OSError',
    'WebSocketException',
  };

  static bool _isNetworkError(Object error) =>
      _networkErrorTypes.contains(error.runtimeType.toString());
}

class _Exchange {
  _Exchange(this.response, this.body);

  final BitmeshResponse response;

  /// The unread body of a successful streamed response.
  final Stream<List<int>>? body;
}
