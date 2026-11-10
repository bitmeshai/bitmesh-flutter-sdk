import 'dart:async';

import 'package:meta/meta.dart';

import 'http/retry_policy.dart';
import 'logging.dart';

/// Returns a current Firebase App Check token, or `null` if none is available.
///
/// Called right before every request attempt, retries and polling included.
/// Return the Firebase SDK's cached token; it refreshes itself:
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
    this.debugToken,
  });

  static const String defaultBaseUrl = 'https://api.bitmesh.ai';

  /// API root, without a version. The SDK calls `{baseUrl}/v2/...`. Override
  /// to point at a staging environment.
  final String baseUrl;

  /// Per-attempt timeout, covering connect, upload and response body read.
  /// For a streamed reply it covers the wait for the response to start.
  ///
  /// With retries enabled the total wall time can exceed this value.
  final Duration timeout;

  final RetryPolicy retryPolicy;

  /// Headers merged into every request. SDK headers win on conflict.
  final Map<String, String> defaultHeaders;

  /// Optional diagnostics sink. The API key and tokens are never logged.
  final BitmeshLogger? logger;

  /// Value for the `User-Agent` header, when the platform allows setting it.
  final String? userAgent;

  /// Supplies the Firebase App Check token sent as `X-Firebase-AppCheck`.
  ///
  /// Required when the API key is a mobile key: the API refuses every request
  /// on such a key without a valid token. Leave it `null` for server keys.
  /// The token is never logged.
  final AppCheckTokenProvider? appCheckTokenProvider;

  /// A Bitmesh debug token (`bmdbg_...`), sent as `X-Bitmesh-Debug-Token` in
  /// place of the App Check token while testing a mobile key on a simulator.
  ///
  /// When set, [appCheckTokenProvider] is not called. Never set it in a
  /// release build: pick it by build mode, e.g. `kDebugMode ? token : null`.
  final String? debugToken;

  BitmeshOptions copyWith({
    String? baseUrl,
    Duration? timeout,
    RetryPolicy? retryPolicy,
    Map<String, String>? defaultHeaders,
    BitmeshLogger? logger,
    String? userAgent,
    AppCheckTokenProvider? appCheckTokenProvider,
    String? debugToken,
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
      debugToken: debugToken ?? this.debugToken,
    );
  }
}
