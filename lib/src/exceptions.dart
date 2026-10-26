import 'dart:convert';

/// Base class for every error thrown by this package.
///
/// Catching [BitmeshException] catches all SDK errors, including transport
/// failures. Catch [BitmeshApiException] to react only to error responses that
/// actually reached the Bitmesh API.
abstract class BitmeshException implements Exception {
  const BitmeshException(this.message);

  /// Human readable description of what went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when the SDK is misconfigured (missing key/secret, bad base URL...).
class BitmeshConfigurationException extends BitmeshException {
  const BitmeshConfigurationException(super.message);
}

/// Thrown when arguments passed to an SDK method are invalid.
class BitmeshArgumentException extends BitmeshException {
  const BitmeshArgumentException(super.message);
}

/// Thrown when the request never produced an HTTP response (DNS failure,
/// connection reset, TLS handshake failure, offline device...).
class BitmeshNetworkException extends BitmeshException {
  const BitmeshNetworkException(super.message, {this.cause});

  /// The underlying error, usually a `SocketException` or `ClientException`.
  final Object? cause;

  @override
  String toString() => 'BitmeshNetworkException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}

/// Thrown when [BitmeshOptions.appCheckTokenProvider] could not supply a
/// token, so the request was not sent.
///
/// On a device this usually means App Check is not set up for the app in the
/// Firebase console (Play Integrity / App Attest registration, debug token).
class BitmeshAppCheckTokenException extends BitmeshException {
  const BitmeshAppCheckTokenException(super.message, {this.cause});

  /// The error thrown by the token provider, if it threw.
  final Object? cause;

  @override
  String toString() => 'BitmeshAppCheckTokenException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}

/// Thrown when a single HTTP attempt exceeded [BitmeshOptions.timeout].
class BitmeshTimeoutException extends BitmeshException {
  const BitmeshTimeoutException(this.timeout, {String? detail})
      : super(detail ?? 'Request timed out.');

  final Duration timeout;

  @override
  String toString() =>
      'BitmeshTimeoutException: $message (${timeout.inMilliseconds}ms)';
}

/// Thrown when a response body could not be parsed into the expected shape.
class BitmeshSerializationException extends BitmeshException {
  const BitmeshSerializationException(super.message, {this.body});

  /// The raw response body, truncated for logging safety.
  final String? body;

  @override
  String toString() => 'BitmeshSerializationException: $message'
      '${body == null ? '' : '\nBody: ${_truncate(body!)}'}';
}

/// Thrown when an asynchronous job did not finish within the polling timeout.
class BitmeshJobTimeoutException extends BitmeshException {
  const BitmeshJobTimeoutException({
    required this.jobId,
    required this.timeout,
    this.lastStatus,
  }) : super('Job did not complete before the polling timeout expired.');

  final String jobId;
  final Duration timeout;

  /// Last status reported by the API before giving up.
  final String? lastStatus;

  @override
  String toString() => 'BitmeshJobTimeoutException: job $jobId did not complete '
      'within ${timeout.inSeconds}s (last status: ${lastStatus ?? 'unknown'}).';
}

/// Thrown when an asynchronous job finished in a failed/cancelled state.
class BitmeshJobFailedException extends BitmeshException {
  const BitmeshJobFailedException({
    required this.jobId,
    required this.status,
    String? detail,
  }) : super(detail ?? 'Job failed.');

  final String jobId;
  final String status;

  @override
  String toString() =>
      'BitmeshJobFailedException: job $jobId ended with status "$status". '
      '$message';
}

/// A non-2xx response returned by the Bitmesh API.
///
/// The API reports errors as `{"error": {"message": ..., "type": ..., "code": ...}}`;
/// those fields are surfaced as [message], [type] and [code] when present.
class BitmeshApiException extends BitmeshException {
  BitmeshApiException({
    required this.statusCode,
    required String message,
    this.body,
    this.code,
    this.type,
    this.retryAfter,
  }) : super(message);

  /// HTTP status code of the response.
  final int statusCode;

  /// Raw response body, useful when the API returns HTML or an unknown shape.
  final String? body;

  /// Machine readable error code, e.g. `insufficient_credits`.
  final String? code;

  /// Error category reported by the API, e.g. `invalid_request_error`.
  final String? type;

  /// Value of the `Retry-After` header, when the server sent one.
  final Duration? retryAfter;

  /// Builds the most specific exception subtype for [statusCode].
  factory BitmeshApiException.fromResponse(
    int statusCode,
    String body, {
    Map<String, String> headers = const {},
  }) {
    final parsed = _parseError(body);
    final message = parsed.message ??
        'Bitmesh API request failed with status $statusCode: '
            '${_truncate(body)}';
    final retryAfter = _parseRetryAfter(headers['retry-after']);

    switch (statusCode) {
      case 400:
      case 422:
        return BitmeshBadRequestException(
          statusCode: statusCode,
          message: message,
          body: body,
          code: parsed.code,
          type: parsed.type,
        );
      case 401:
        if (_isAppCheckError(message)) {
          return BitmeshAppCheckRejectedException(
            statusCode: statusCode,
            message: message,
            body: body,
            code: parsed.code,
            type: parsed.type,
          );
        }
        return BitmeshAuthenticationException(
          statusCode: statusCode,
          message: message,
          body: body,
          code: parsed.code,
          type: parsed.type,
        );
      case 403:
        return BitmeshAuthenticationException(
          statusCode: statusCode,
          message: message,
          body: body,
          code: parsed.code,
          type: parsed.type,
        );
      case 404:
        return BitmeshNotFoundException(
          statusCode: statusCode,
          message: message,
          body: body,
          code: parsed.code,
          type: parsed.type,
        );
      case 429:
        return BitmeshRateLimitException(
          statusCode: statusCode,
          message: message,
          body: body,
          code: parsed.code,
          type: parsed.type,
          retryAfter: retryAfter,
        );
    }

    if (statusCode >= 500) {
      return BitmeshServerException(
        statusCode: statusCode,
        message: message,
        body: body,
        code: parsed.code,
        type: parsed.type,
        retryAfter: retryAfter,
      );
    }

    return BitmeshApiException(
      statusCode: statusCode,
      message: message,
      body: body,
      code: parsed.code,
      type: parsed.type,
      retryAfter: retryAfter,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: [$statusCode] $message');
    if (type != null) buffer.write(' (type: $type)');
    if (code != null) buffer.write(' (code: $code)');
    return buffer.toString();
  }
}

/// 400 / 422 — the request was rejected as invalid.
class BitmeshBadRequestException extends BitmeshApiException {
  BitmeshBadRequestException({
    required super.statusCode,
    required super.message,
    super.body,
    super.code,
    super.type,
  });
}

/// 401 / 403 — the key/secret pair was rejected or lacks access.
class BitmeshAuthenticationException extends BitmeshApiException {
  BitmeshAuthenticationException({
    required super.statusCode,
    required super.message,
    super.body,
    super.code,
    super.type,
  });
}

/// 401 — the API key is a mobile key and the request's App Check token was
/// missing or failed verification. [message] names the reason, for example
/// `App Check token is for an unregistered app`.
///
/// A subtype of [BitmeshAuthenticationException], so existing handlers still
/// catch it.
class BitmeshAppCheckRejectedException extends BitmeshAuthenticationException {
  BitmeshAppCheckRejectedException({
    required super.statusCode,
    required super.message,
    super.body,
    super.code,
    super.type,
  });

  /// True when the API could not verify tokens at all, rather than rejecting
  /// this one. Worth retrying after a pause; nothing on the device is wrong.
  bool get isTemporary => message.contains('temporarily unavailable');
}

/// 404 — unknown endpoint, or a job id that does not exist.
class BitmeshNotFoundException extends BitmeshApiException {
  BitmeshNotFoundException({
    required super.statusCode,
    required super.message,
    super.body,
    super.code,
    super.type,
  });
}

/// 429 — rate limited. Check [BitmeshApiException.retryAfter] before retrying.
class BitmeshRateLimitException extends BitmeshApiException {
  BitmeshRateLimitException({
    required super.statusCode,
    required super.message,
    super.body,
    super.code,
    super.type,
    super.retryAfter,
  });
}

/// 5xx — the API failed to handle an otherwise valid request.
class BitmeshServerException extends BitmeshApiException {
  BitmeshServerException({
    required super.statusCode,
    required super.message,
    super.body,
    super.code,
    super.type,
    super.retryAfter,
  });
}

class _ParsedError {
  const _ParsedError({this.message, this.code, this.type});
  final String? message;
  final String? code;
  final String? type;
}

_ParsedError _parseError(String body) {
  if (body.trim().isEmpty) return const _ParsedError();
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const _ParsedError();

    final error = decoded['error'];
    final source = error is Map ? error : decoded;

    final message = source['message'] ?? source['detail'] ?? source['error'];
    return _ParsedError(
      message: message is String && message.isNotEmpty ? message : null,
      code: source['code']?.toString(),
      type: source['type']?.toString(),
    );
  } on FormatException {
    return const _ParsedError();
  }
}

// Every App Check failure message from the API names App Check or its header.
bool _isAppCheckError(String message) =>
    message.contains('App Check') || message.contains('X-Firebase-AppCheck');

Duration? _parseRetryAfter(String? headerValue) {
  if (headerValue == null) return null;
  final seconds = int.tryParse(headerValue.trim());
  if (seconds != null) return Duration(seconds: seconds);

  // The header may also be an HTTP date.
  try {
    final date = DateTime.parse(headerValue.trim());
    final delta = date.difference(DateTime.now());
    return delta.isNegative ? Duration.zero : delta;
  } on FormatException {
    return null;
  }
}

String _truncate(String value, [int max = 512]) =>
    value.length <= max ? value : '${value.substring(0, max)}… (truncated)';
