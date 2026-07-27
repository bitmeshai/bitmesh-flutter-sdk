import 'package:meta/meta.dart';

import 'exceptions.dart';

/// A Bitmesh consumer key/secret pair.
///
/// Never hardcode these in a shipped app. Load them at runtime from Firebase
/// Remote Config, your own backend, `--dart-define`, or secure storage.
@immutable
class BitmeshCredentials {
  /// Creates credentials, rejecting empty values early.
  factory BitmeshCredentials({required String key, required String secret}) {
    final trimmedKey = key.trim();
    final trimmedSecret = secret.trim();
    if (trimmedKey.isEmpty || trimmedSecret.isEmpty) {
      throw const BitmeshConfigurationException(
        'Bitmesh key and secret must both be non-empty. '
        'Check that your remote config / environment values are published.',
      );
    }
    return BitmeshCredentials._(trimmedKey, trimmedSecret);
  }

  const BitmeshCredentials._(this.key, this.secret);

  /// Reads credentials out of an arbitrary config map.
  ///
  /// Useful with Firebase Remote Config:
  ///
  /// ```dart
  /// BitmeshCredentials.fromMap({
  ///   'bitmesh_key': remoteConfig.getString('bitmesh_key'),
  ///   'bitmesh_secret': remoteConfig.getString('bitmesh_secret'),
  /// });
  /// ```
  factory BitmeshCredentials.fromMap(
    Map<String, Object?> values, {
    String keyName = 'bitmesh_key',
    String secretName = 'bitmesh_secret',
  }) {
    return BitmeshCredentials(
      key: values[keyName]?.toString() ?? '',
      secret: values[secretName]?.toString() ?? '',
    );
  }

  /// Reads credentials from the `BITMESH_KEY` / `BITMESH_SECRET`
  /// `--dart-define` values.
  ///
  /// `String.fromEnvironment` only resolves compile-time constant names, so the
  /// names are fixed. For other names, call the default constructor with your
  /// own `String.fromEnvironment(...)` values.
  factory BitmeshCredentials.fromEnvironment() {
    return BitmeshCredentials(
      key: const String.fromEnvironment('BITMESH_KEY'),
      secret: const String.fromEnvironment('BITMESH_SECRET'),
    );
  }

  final String key;
  final String secret;

  @override
  String toString() =>
      'BitmeshCredentials(key: ${_redact(key)}, secret: ${_redact(secret)})';

  @override
  bool operator ==(Object other) =>
      other is BitmeshCredentials && other.key == key && other.secret == secret;

  @override
  int get hashCode => Object.hash(key, secret);

  static String _redact(String value) {
    if (value.length <= 4) return '***';
    return '${value.substring(0, 2)}***${value.substring(value.length - 2)}'
        ' (len ${value.length})';
  }
}
