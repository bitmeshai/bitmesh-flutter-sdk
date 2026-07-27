import 'dart:convert';
import 'dart:math';

import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// Verbatim copy of the signing code from the original in-app `BitmeshClient`.
///
/// The package must keep producing identical signatures, so these functions act
/// as the reference oracle for the tests below.
class _LegacySigner {
  _LegacySigner(this.key, this.secret);

  final String key;
  final String secret;

  String generateSignature(
    String method,
    String url,
    Map<String, String> params,
  ) {
    final uri = Uri.parse(url);
    var normalizedUrl = '${uri.scheme}://${uri.host}';
    final port = uri.hasPort ? uri.port : null;
    if (port != null &&
        !((uri.scheme == 'http' && port == 80) ||
            (uri.scheme == 'https' && port == 443))) {
      normalizedUrl += ':$port';
    }
    normalizedUrl += '/${uri.path.replaceAll(RegExp(r'^/'), '')}';

    final allParams = {...params, ...uri.queryParameters}
      ..remove('oauth_signature');
    final sortedKeys = allParams.keys.toList()..sort();
    final normalizedParams = sortedKeys
        .map((k) =>
            '${Uri.encodeComponent(k)}=${Uri.encodeComponent(allParams[k]!)}')
        .join('&');

    final base = '${Uri.encodeComponent(method.toUpperCase())}'
        '&${Uri.encodeComponent(normalizedUrl)}'
        '&${Uri.encodeComponent(normalizedParams)}';

    final signingKey = '${Uri.encodeComponent(secret)}&';
    final digest =
        Hmac(sha1, utf8.encode(signingKey)).convert(utf8.encode(base));
    return base64.encode(digest.bytes);
  }

  String buildAuthorizationHeader(Map<String, String> params) {
    final parts = params.entries
        .where((e) => e.key.startsWith('oauth_'))
        .map((e) =>
            '${Uri.encodeComponent(e.key)}="${Uri.encodeComponent(e.value)}"')
        .join(', ');
    return 'OAuth $parts';
  }

  String payloadSignature(String body, String oauthSig) =>
      sha256.convert(utf8.encode(body + key + oauthSig)).toString();

  String multipartPayloadSignature(
    Map<String, dynamic> fields,
    String oauthSig,
  ) {
    final sorted = Map.fromEntries(
      fields.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final data = utf8.encode(jsonEncode(sorted) + key + oauthSig);
    return sha256.convert(data).toString();
  }
}

void main() {
  const key = 'consumer-key-123';
  const secret = 'consumer~secret/456+with spaces';

  final credentials = BitmeshCredentials(key: key, secret: secret);
  final legacy = _LegacySigner(key, secret);

  OAuth1Signer newSigner({int seed = 7, DateTime? now}) => OAuth1Signer(
        credentials: credentials,
        random: Random(seed),
        clock: () => now ?? DateTime.utc(2026, 7, 27, 12, 0, 0),
      );

  group('signature compatibility with the original client', () {
    final urls = [
      'https://api.bitmesh.ai/chat',
      'https://api.bitmesh.ai/video/abc-123',
      'https://api.bitmesh.ai/video/abc?include=outputs&verbose=true',
      'https://api.bitmesh.ai/transcribe-recorded/id%20with%20space',
      'https://api.bitmesh.ai:8443/tools/general/background-removal',
      'http://localhost:8080/chat',
    ];

    for (final url in urls) {
      for (final method in ['GET', 'POST']) {
        test('$method $url', () {
          final uri = Uri.parse(url);
          final params = <String, String>{
            'oauth_consumer_key': key,
            'oauth_signature_method': 'HMAC-SHA1',
            'oauth_timestamp': '1785153600',
            'oauth_nonce': 'deadbeefcafebabe0011223344556677',
            'oauth_version': '1.0',
          };

          expect(
            newSigner().generateSignature(method, uri, params),
            equals(legacy.generateSignature(method, url, params)),
          );
        });
      }
    }

    test('authorization header matches', () {
      final params = newSigner().generateParams('POST', Uri.parse(
        'https://api.bitmesh.ai/chat',
      ));
      expect(
        newSigner().authorizationHeader(params),
        equals(legacy.buildAuthorizationHeader(params)),
      );
    });

    test('payload signature matches for JSON bodies', () {
      final body = jsonEncode({
        'model': 'bitmeshai/chat-now-nano',
        'messages': [
          {'role': 'user', 'content': 'héllo — unicode ✓'},
        ],
      });
      const oauthSig = 'BASE64SIGNATURE+/=';
      expect(
        newSigner().payloadSignature(body, oauthSig),
        equals(legacy.payloadSignature(body, oauthSig)),
      );
    });

    test('payload signature matches for empty GET bodies', () {
      const oauthSig = 'anothersig==';
      expect(
        newSigner().payloadSignature('', oauthSig),
        equals(legacy.payloadSignature('', oauthSig)),
      );
    });

    test('multipart payload signature matches, including key ordering', () {
      final fields = <String, dynamic>{
        'zeta': 1,
        'alpha': 'a',
        'nested': {'b': 2, 'a': 1},
        'speech_models': ['whisper', 'nova'],
      };
      const oauthSig = 'multipart-sig';
      expect(
        newSigner().multipartPayloadSignature(fields, oauthSig),
        equals(legacy.multipartPayloadSignature(fields, oauthSig)),
      );
    });
  });

  group('OAuth parameters', () {
    test('contain the required fields and a signature', () {
      final params =
          newSigner().generateParams('POST', Uri.parse('https://api.bitmesh.ai/chat'));

      expect(params['oauth_consumer_key'], key);
      expect(params['oauth_signature_method'], 'HMAC-SHA1');
      expect(params['oauth_version'], '1.0');
      expect(params['oauth_timestamp'], '1785153600');
      expect(params['oauth_nonce'], hasLength(32));
      expect(params['oauth_signature'], isNotEmpty);
    });

    test('nonce is 128 bits of hex and changes per request', () {
      final signer = OAuth1Signer(credentials: credentials);
      final nonces = List.generate(50, (_) => signer.generateNonce());

      expect(nonces.toSet(), hasLength(50));
      for (final nonce in nonces) {
        expect(nonce, matches(RegExp(r'^[0-9a-f]{32}$')));
      }
    });

    test('signature base string excludes oauth_signature itself', () {
      final signer = newSigner();
      final params = signer.generateParams(
        'GET',
        Uri.parse('https://api.bitmesh.ai/video/1'),
      );

      final base = signer.signatureBaseString(
        'GET',
        Uri.parse('https://api.bitmesh.ai/video/1'),
        params,
      );
      expect(base, isNot(contains('oauth_signature%3D')));
      expect(base, contains('oauth_consumer_key'));
    });

    test('query parameters take part in the signature', () {
      final signer = newSigner();
      const params = {
        'oauth_consumer_key': key,
        'oauth_nonce': 'n',
        'oauth_timestamp': '1',
      };

      final withoutQuery = signer.generateSignature(
        'GET',
        Uri.parse('https://api.bitmesh.ai/video/1'),
        params,
      );
      final withQuery = signer.generateSignature(
        'GET',
        Uri.parse('https://api.bitmesh.ai/video/1?verbose=true'),
        params,
      );

      expect(withQuery, isNot(equals(withoutQuery)));
    });

    test('default https port is not part of the normalised URL', () {
      final signer = newSigner();
      const params = {'oauth_nonce': 'n'};

      expect(
        signer.generateSignature(
            'GET', Uri.parse('https://api.bitmesh.ai:443/chat'), params),
        equals(signer.generateSignature(
            'GET', Uri.parse('https://api.bitmesh.ai/chat'), params)),
      );
    });
  });

  group('credentials', () {
    test('reject empty values', () {
      expect(() => BitmeshCredentials(key: '', secret: 's'),
          throwsA(isA<BitmeshConfigurationException>()));
      expect(() => BitmeshCredentials(key: 'k', secret: '   '),
          throwsA(isA<BitmeshConfigurationException>()));
    });

    test('trim whitespace pasted in from consoles', () {
      final creds = BitmeshCredentials(key: ' k ', secret: '\ts\n');
      expect(creds.key, 'k');
      expect(creds.secret, 's');
    });

    test('never print the secret', () {
      final text = BitmeshCredentials(key: key, secret: secret).toString();
      expect(text, isNot(contains(secret)));
      expect(text, isNot(contains(key)));
    });

    test('read from a remote-config style map', () {
      final creds = BitmeshCredentials.fromMap({
        'bitmesh_key': key,
        'bitmesh_secret': secret,
      });
      expect(creds.key, key);
      expect(creds.secret, secret);
    });
  });
}
