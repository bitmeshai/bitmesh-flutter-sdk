import 'package:meta/meta.dart';

import 'http/retry_policy.dart';
import 'logging.dart';

/// Transport-level configuration shared by every request.
@immutable
class BitmeshOptions {
  const BitmeshOptions({
    this.baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 30),
    this.retryPolicy = const RetryPolicy(),
    this.defaultHeaders = const {},
    this.logger,
    this.userAgent,
  });

  static const String defaultBaseUrl = 'https://api.bitmesh.ai';

  /// API root. Override to point at a staging environment or a proxy.
  final String baseUrl;

  /// Per-attempt timeout, covering connect, upload and response body read.
  ///
  /// With retries enabled the total wall time can exceed this value.
  final Duration timeout;

  final RetryPolicy retryPolicy;

  /// Headers merged into every request. SDK headers win on conflict.
  final Map<String, String> defaultHeaders;

  /// Optional diagnostics sink. Credentials are never logged.
  final BitmeshLogger? logger;

  /// Value for the `User-Agent` header, when the platform allows setting it.
  final String? userAgent;

  BitmeshOptions copyWith({
    String? baseUrl,
    Duration? timeout,
    RetryPolicy? retryPolicy,
    Map<String, String>? defaultHeaders,
    BitmeshLogger? logger,
    String? userAgent,
  }) {
    return BitmeshOptions(
      baseUrl: baseUrl ?? this.baseUrl,
      timeout: timeout ?? this.timeout,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      logger: logger ?? this.logger,
      userAgent: userAgent ?? this.userAgent,
    );
  }
}
