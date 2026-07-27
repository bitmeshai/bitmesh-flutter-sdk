/// Severity of a message emitted by the SDK.
enum BitmeshLogLevel { debug, info, warning, error }

/// Sink for the SDK's diagnostic output.
///
/// The SDK never logs credentials or signatures. Provide your own
/// implementation to forward messages to your app's logger (Crashlytics,
/// Sentry, `debugPrint`, ...).
abstract class BitmeshLogger {
  const BitmeshLogger();

  void log(
    BitmeshLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  });
}

/// Prints SDK diagnostics to stdout. Handy during development.
class ConsoleBitmeshLogger extends BitmeshLogger {
  const ConsoleBitmeshLogger({this.minimumLevel = BitmeshLogLevel.debug});

  final BitmeshLogLevel minimumLevel;

  @override
  void log(
    BitmeshLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) return;
    // ignore: avoid_print
    print('[bitmesh][${level.name}] $message'
        '${error == null ? '' : '\n  error: $error'}');
  }
}

/// Forwards SDK diagnostics to a plain callback, e.g. Flutter's `debugPrint`.
class CallbackBitmeshLogger extends BitmeshLogger {
  const CallbackBitmeshLogger(
    this.onMessage, {
    this.minimumLevel = BitmeshLogLevel.debug,
  });

  final void Function(String message) onMessage;
  final BitmeshLogLevel minimumLevel;

  @override
  void log(
    BitmeshLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) return;
    onMessage('[bitmesh][${level.name}] $message'
        '${error == null ? '' : ' | error: $error'}');
  }
}
