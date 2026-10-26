import 'dart:async';

import 'package:meta/meta.dart';

import 'http/retry_policy.dart';
import 'logging.dart';

/// Returns a current Firebase App Check token, or `null` if none is available.
///
/// Called right before every signed request attempt, retries and polling
/// included. Return the Firebase SDK's cached token; it refreshes itself:
///
/// ```dart
/// appCheckTokenProvider: () => FirebaseAppCheck.instance.getToken(),
/// ```
typedef AppCheckTokenProvider = FutureOr<String?> Function();

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
    this.appCheckTokenProvider,
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

  /// Supplies the Firebase App Check token sent as `X-Firebase-AppCheck`.
  ///
  /// Required when the API key is a mobile key: the API refuses every request
  /// on such a key without a valid token. Leave it `null` for server keys.
  /// The token is not part of either signature, and is never logged.
  final AppCheckTokenProvider? appCheckTokenProvider;

  BitmeshOptions copyWith({
    String? baseUrl,
    Duration? timeout,
    RetryPolicy? retryPolicy,
    Map<String, String>? defaultHeaders,
    BitmeshLogger? logger,
    String? userAgent,
    AppCheckTokenProvider? appCheckTokenProvider,
  }) {
    return BitmeshOptions(
      baseUrl: baseUrl ?? this.baseUrl,
      timeout: timeout ?? this.timeout,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      logger: logger ?? this.logger,
      userAgent: userAgent ?? this.userAgent,
      appCheckTokenProvider:
          appCheckTokenProvider ?? this.appCheckTokenProvider,
    );
  }
}
