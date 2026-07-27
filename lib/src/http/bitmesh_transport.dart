import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/oauth1_signer.dart';
import '../bitmesh_file.dart';
import '../bitmesh_options.dart';
import '../exceptions.dart';
import '../logging.dart';

/// A completed HTTP exchange.
class BitmeshResponse {
  BitmeshResponse({
    required this.statusCode,
    required this.bodyBytes,
    required this.headers,
  });

  final int statusCode;
  final Uint8List bodyBytes;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  late final String body = _decodeBody();

  String _decodeBody() {
    try {
      return utf8.decode(bodyBytes);
    } on FormatException {
      return utf8.decode(bodyBytes, allowMalformed: true);
    }
  }
}

/// Signs, sends and retries HTTP requests against the Bitmesh API.
///
/// This is the only layer that talks to `package:http`. Every request is signed
/// per attempt, so retried requests carry a fresh nonce and timestamp.
class BitmeshTransport {
  BitmeshTransport({
    required this.signer,
    required this.options,
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null {
    final parsed = Uri.tryParse(options.baseUrl);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw BitmeshConfigurationException(
        'Invalid baseUrl "${options.baseUrl}". Expected an absolute URL such as '
        '"https://api.bitmesh.ai".',
      );
    }
  }

  final OAuth1Signer signer;
  final BitmeshOptions options;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  BitmeshLogger? get _logger => options.logger;

  /// Signed `POST` with a JSON body, returning a decoded JSON object.
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) async {
    final uri = buildUri(path);
    final jsonBody = jsonEncode(payload);

    final response = await _send(
      method: method,
      uri: uri,
      idempotent: false,
      buildRequest: () async {
        final oauth = signer.generateParams(method, uri);
        return http.Request(method, uri)
          ..headers.addAll(_headers(
            oauth: oauth,
            payloadSignature:
                signer.payloadSignature(jsonBody, oauth['oauth_signature']!),
            contentType: 'application/json',
          ))
          ..body = jsonBody;
      },
    );

    return decodeJsonObject(response.body);
  }

  /// Signed `GET`, returning a decoded JSON object.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final uri = buildUri(path, query: query);

    final response = await _send(
      method: 'GET',
      uri: uri,
      idempotent: true,
      buildRequest: () async {
        final oauth = signer.generateParams('GET', uri);
        return http.Request('GET', uri)
          ..headers.addAll(_headers(
            oauth: oauth,
            payloadSignature:
                signer.payloadSignature('', oauth['oauth_signature']!),
          ));
      },
    );

    return decodeJsonObject(response.body);
  }

  /// Signed `multipart/form-data` `POST`, returning a decoded JSON object.
  ///
  /// [fields] may be nested; nested maps are flattened to `parent[child]` form
  /// field names, while the payload signature covers the un-flattened JSON.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    Map<String, dynamic> fields = const {},
    List<BitmeshFile> files = const [],
  }) async {
    for (final file in files) {
      file.validate();
    }

    final uri = buildUri(path);
    final flatFields = flattenFields(fields);

    final response = await _send(
      method: 'POST',
      uri: uri,
      idempotent: false,
      buildRequest: () async {
        final oauth = signer.generateParams('POST', uri);
        final request = http.MultipartRequest('POST', uri)
          ..headers.addAll(_headers(
            oauth: oauth,
            payloadSignature: signer.multipartPayloadSignature(
              fields,
              oauth['oauth_signature']!,
            ),
          ));

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

    return decodeJsonObject(response.body);
  }

  /// Unsigned `GET` for public result URLs (`/imgrslt/...`, tool outputs).
  Future<BitmeshResponse> getPublic(String path) {
    final uri = buildUri(path);
    return _send(
      method: 'GET',
      uri: uri,
      idempotent: true,
      buildRequest: () async => http.Request('GET', uri)
        ..headers.addAll({
          ...options.defaultHeaders,
          if (options.userAgent != null) 'User-Agent': options.userAgent!,
        }),
    );
  }

  /// Builds an absolute URL from a path relative to [BitmeshOptions.baseUrl].
  ///
  /// Query values are encoded exactly as the API's signature verification
  /// expects, so the resulting [Uri] can be signed as-is.
  Uri buildUri(String path, {Map<String, String> query = const {}}) {
    final base = options.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final relative = path.replaceAll(RegExp(r'^/+'), '');
    final queryString = query.isEmpty
        ? ''
        : '?${query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return Uri.parse('$base/$relative$queryString');
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
      if (value is Map<String, dynamic>) {
        result.addAll(flattenFields(value, name));
      } else if (value is Map) {
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

  Map<String, String> _headers({
    required Map<String, String> oauth,
    required String payloadSignature,
    String? contentType,
  }) {
    return {
      ...options.defaultHeaders,
      if (options.userAgent != null) 'User-Agent': options.userAgent!,
      'Authorization': signer.authorizationHeader(oauth),
      'X-Payload-Signature': payloadSignature,
      'Accept': 'application/json',
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  Future<BitmeshResponse> _send({
    required String method,
    required Uri uri,
    required bool idempotent,
    required Future<http.BaseRequest> Function() buildRequest,
  }) async {
    final policy = options.retryPolicy;
    var attempt = 0;

    while (true) {
      attempt++;
      final isLastAttempt = attempt >= policy.maxAttempts;

      try {
        final response = await _attempt(method, uri, buildRequest);

        if (response.isSuccess) {
          _log(BitmeshLogLevel.debug,
              '$method ${uri.path} -> ${response.statusCode}');
          return response;
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

  Future<BitmeshResponse> _attempt(
    String method,
    Uri uri,
    Future<http.BaseRequest> Function() buildRequest,
  ) async {
    try {
      return await _exchange(buildRequest).timeout(options.timeout);
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

  Future<BitmeshResponse> _exchange(
    Future<http.BaseRequest> Function() buildRequest,
  ) async {
    final request = await buildRequest();
    final streamed = await _httpClient.send(request);
    final bytes = await streamed.stream.toBytes();
    return BitmeshResponse(
      statusCode: streamed.statusCode,
      bodyBytes: bytes,
      headers: streamed.headers,
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
