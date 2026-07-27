import 'package:meta/meta.dart';

import 'exceptions.dart';
import 'models/job_status.dart';

/// How `waitFor*` helpers poll an asynchronous job.
@immutable
class PollingOptions {
  const PollingOptions({
    this.interval = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 10),
    this.backoffFactor = 1.0,
    this.maxInterval = const Duration(seconds: 15),
    this.initialDelay = Duration.zero,
    this.throwOnFailure = true,
  }) : assert(backoffFactor >= 1.0, 'backoffFactor must be >= 1.0');

  /// Delay between polls.
  final Duration interval;

  /// Give up after this much total time and throw [BitmeshJobTimeoutException].
  final Duration timeout;

  /// Multiplier applied to [interval] after each poll, capped at [maxInterval].
  /// `1.0` polls at a fixed rate.
  final double backoffFactor;

  final Duration maxInterval;

  /// Wait this long before the first poll.
  final Duration initialDelay;

  /// Throw [BitmeshJobFailedException] when the job ends failed/cancelled.
  /// When false, the failed job is returned instead.
  final bool throwOnFailure;

  PollingOptions copyWith({
    Duration? interval,
    Duration? timeout,
    double? backoffFactor,
    Duration? maxInterval,
    Duration? initialDelay,
    bool? throwOnFailure,
  }) {
    return PollingOptions(
      interval: interval ?? this.interval,
      timeout: timeout ?? this.timeout,
      backoffFactor: backoffFactor ?? this.backoffFactor,
      maxInterval: maxInterval ?? this.maxInterval,
      initialDelay: initialDelay ?? this.initialDelay,
      throwOnFailure: throwOnFailure ?? this.throwOnFailure,
    );
  }
}

/// Polls [fetch] until the job reaches a terminal state.
///
/// [onUpdate] is called after every poll, which makes it easy to drive a
/// progress indicator.
Future<T> pollJob<T>({
  required String jobId,
  required Future<T> Function() fetch,
  required JobStatus Function(T job) statusOf,
  required String? Function(T job) errorOf,
  PollingOptions options = const PollingOptions(),
  void Function(T job)? onUpdate,
}) async {
  if (options.interval <= Duration.zero) {
    throw const BitmeshArgumentException(
      'PollingOptions.interval must be greater than zero.',
    );
  }

  final deadline = DateTime.now().add(options.timeout);
  var interval = options.interval;

  if (options.initialDelay > Duration.zero) {
    await Future<void>.delayed(options.initialDelay);
  }

  while (true) {
    final job = await fetch();
    onUpdate?.call(job);

    final status = statusOf(job);
    if (status.isSuccess) return job;

    if (status.isTerminal) {
      if (!options.throwOnFailure) return job;
      throw BitmeshJobFailedException(
        jobId: jobId,
        status: status.name,
        detail: errorOf(job) ?? 'The API reported status "${status.name}".',
      );
    }

    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw BitmeshJobTimeoutException(
        jobId: jobId,
        timeout: options.timeout,
        lastStatus: status.name,
      );
    }

    final wait = interval < remaining ? interval : remaining;
    await Future<void>.delayed(wait);

    if (options.backoffFactor > 1.0) {
      final next = Duration(
        microseconds:
            (interval.inMicroseconds * options.backoffFactor).round(),
      );
      interval = next > options.maxInterval ? options.maxInterval : next;
    }
  }
}
