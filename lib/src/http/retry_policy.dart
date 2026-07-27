import 'dart:math';

import 'package:meta/meta.dart';

final Random _jitterRandom = Random();

/// Controls automatic retries of failed requests.
///
/// Retries use exponential backoff with full jitter. A `Retry-After` header on
/// a 429/503 response always wins over the computed delay.
///
/// Safe (GET) requests retry on the full [retryableStatusCodes] set. Writes
/// (POST) only retry on [writeRetryableStatusCodes] by default, because a 5xx
/// may mean the job was created and the response was lost — retrying could
/// charge you twice. Set [retryWritesOnServerError] if your workload prefers
/// availability over exactly-once.
@immutable
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 400),
    this.maxDelay = const Duration(seconds: 10),
    this.backoffFactor = 2.0,
    this.retryableStatusCodes = const {408, 425, 429, 500, 502, 503, 504},
    this.writeRetryableStatusCodes = const {408, 425, 429},
    this.retryWritesOnServerError = false,
    this.retryNetworkErrors = true,
    this.useJitter = true,
  }) : assert(maxAttempts >= 1, 'maxAttempts must be at least 1');

  /// Disables retries entirely.
  const RetryPolicy.none() : this(maxAttempts: 1);

  /// Total attempts, including the first one. `1` disables retries.
  final int maxAttempts;

  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffFactor;

  /// Statuses retried for safe (GET) requests.
  final Set<int> retryableStatusCodes;

  /// Statuses retried for non-idempotent (POST) requests.
  final Set<int> writeRetryableStatusCodes;

  /// When true, POSTs also retry on the full [retryableStatusCodes] set.
  final bool retryWritesOnServerError;

  /// Retry connection failures and timeouts.
  final bool retryNetworkErrors;

  /// Randomise backoff to avoid thundering herds.
  final bool useJitter;

  bool get isEnabled => maxAttempts > 1;

  /// Whether a response with [statusCode] should be retried.
  bool shouldRetryStatus(int statusCode, {required bool idempotent}) {
    if (idempotent || retryWritesOnServerError) {
      return retryableStatusCodes.contains(statusCode);
    }
    return writeRetryableStatusCodes.contains(statusCode);
  }

  /// Delay before attempt number [attempt] (1-based: the delay after the first
  /// failure is `delayFor(1)`).
  Duration delayFor(int attempt, {Duration? retryAfter}) {
    if (retryAfter != null) {
      return retryAfter > maxDelay ? maxDelay : retryAfter;
    }
    final exponential = initialDelay.inMicroseconds *
        pow(backoffFactor, (attempt - 1).clamp(0, 30));
    final capped = min(exponential.toDouble(), maxDelay.inMicroseconds.toDouble());
    final micros = useJitter ? _jitterRandom.nextDouble() * capped : capped;
    return Duration(microseconds: micros.round());
  }

  RetryPolicy copyWith({
    int? maxAttempts,
    Duration? initialDelay,
    Duration? maxDelay,
    double? backoffFactor,
    Set<int>? retryableStatusCodes,
    Set<int>? writeRetryableStatusCodes,
    bool? retryWritesOnServerError,
    bool? retryNetworkErrors,
    bool? useJitter,
  }) {
    return RetryPolicy(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      initialDelay: initialDelay ?? this.initialDelay,
      maxDelay: maxDelay ?? this.maxDelay,
      backoffFactor: backoffFactor ?? this.backoffFactor,
      retryableStatusCodes: retryableStatusCodes ?? this.retryableStatusCodes,
      writeRetryableStatusCodes:
          writeRetryableStatusCodes ?? this.writeRetryableStatusCodes,
      retryWritesOnServerError:
          retryWritesOnServerError ?? this.retryWritesOnServerError,
      retryNetworkErrors: retryNetworkErrors ?? this.retryNetworkErrors,
      useJitter: useJitter ?? this.useJitter,
    );
  }
}
