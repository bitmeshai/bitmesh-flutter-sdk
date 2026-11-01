import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../bitmesh_credentials.dart';

/// Signs requests for Bitmesh's 0-legged OAuth 1.0a scheme.
///
/// Every request carries two independent signatures:
///
/// * `Authorization: OAuth ...` — HMAC-SHA1 over the OAuth signature base
///   string, keyed with `encode(secret) + "&"` (no token secret).
/// * `X-Payload-Signature` — `sha256(body + consumerKey + oauthSignature)`.
///
/// The encodings here intentionally mirror the server implementation: they use
/// [Uri.encodeComponent] rather than strict RFC 3986 percent-encoding. Changing
/// that would produce signatures the API rejects.
class OAuth1Signer {
  OAuth1Signer({
    required this.credentials,
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final BitmeshCredentials credentials;
  final Random _random;
  final DateTime Function() _clock;

  /// Builds the OAuth parameter set (including `oauth_signature`) for a request.
  Map<String, String> generateParams(String method, Uri url) {
    final params = <String, String>{
      'oauth_consumer_key': credentials.key,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp':
          (_clock().millisecondsSinceEpoch ~/ 1000).toString(),
      'oauth_nonce': generateNonce(),
      'oauth_version': '1.0',
    };
    params['oauth_signature'] = generateSignature(method, url, params);
    return params;
  }

  /// Renders the `Authorization` header value from [params].
  String authorizationHeader(Map<String, String> params) {
    final parts = params.entries
        .where((e) => e.key.startsWith('oauth_'))
        .map((e) =>
            '${Uri.encodeComponent(e.key)}="${Uri.encodeComponent(e.value)}"')
        .join(', ');
    return 'OAuth $parts';
  }

  /// 128-bit hex nonce.
  String generateNonce() => List<int>.generate(16, (_) => _random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  /// `X-Payload-Signature` for a request with a textual body.
  ///
  /// Pass an empty string for bodyless requests such as `GET`.
  String payloadSignature(String body, String oauthSignature) =>
      sha256.convert(utf8.encode(body + credentials.key + oauthSignature))
          .toString();

  /// `X-Payload-Signature` for a multipart request.
  ///
  /// The signature covers the JSON encoding of the non-file fields as the
  /// server receives them, with the **top-level** keys sorted — not the
  /// flattened form-field names actually sent on the wire. Multipart carries
  /// text, so values are first converted with [multipartWireFields]; the server
  /// then trims every string and turns empty strings into `null`. With no
  /// fields at all the server hashes `[]`, not `{}`.
  String multipartPayloadSignature(
    Map<String, dynamic> fields,
    String oauthSignature,
  ) {
    final received = _asReceived(multipartWireFields(fields)) as Map;
    if (received.isEmpty) return payloadSignature('[]', oauthSignature);

    final keys = received.keys.map((k) => k.toString()).toList()..sort();
    final sorted = {for (final k in keys) k: received[k]};
    return payloadSignature(jsonEncode(sorted), oauthSignature);
  }

  /// The multipart fields as they go over the wire: booleans become `"1"` or
  /// `"0"`, numbers their string form, and `null`s and empty collections are
  /// left out. Nested maps and lists are kept for flattening.
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

  /// Mirrors the server's TrimStrings and ConvertEmptyStringsToNull.
  static Object? _asReceived(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is Map) {
      return {for (final e in value.entries) e.key: _asReceived(e.value)};
    }
    if (value is List) return value.map(_asReceived).toList();
    return value;
  }

  /// HMAC-SHA1 OAuth signature, base64 encoded.
  String generateSignature(String method, Uri url, Map<String, String> params) {
    final base = signatureBaseString(method, url, params);
    final signingKey = '${Uri.encodeComponent(credentials.secret)}&';
    final digest =
        Hmac(sha1, utf8.encode(signingKey)).convert(utf8.encode(base));
    return base64.encode(digest.bytes);
  }

  /// Exposed for testing: the string that gets HMAC'd.
  String signatureBaseString(
    String method,
    Uri url,
    Map<String, String> params,
  ) {
    final normalizedUrl = _normalizeUrl(url);

    final allParams = <String, String>{...params, ...url.queryParameters}
      ..remove('oauth_signature');
    final sortedKeys = allParams.keys.toList()..sort();
    final normalizedParams = sortedKeys
        .map((k) =>
            '${Uri.encodeComponent(k)}=${Uri.encodeComponent(allParams[k]!)}')
        .join('&');

    return '${Uri.encodeComponent(method.toUpperCase())}'
        '&${Uri.encodeComponent(normalizedUrl)}'
        '&${Uri.encodeComponent(normalizedParams)}';
  }

  String _normalizeUrl(Uri uri) {
    var normalized = '${uri.scheme}://${uri.host}';
    if (uri.hasPort &&
        !((uri.scheme == 'http' && uri.port == 80) ||
            (uri.scheme == 'https' && uri.port == 443))) {
      normalized += ':${uri.port}';
    }
    normalized += '/${uri.path.replaceAll(RegExp(r'^/'), '')}';
    return normalized;
  }
}
