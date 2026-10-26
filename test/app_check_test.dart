import 'dart:convert';

import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final credentials = BitmeshCredentials(key: 'key', secret: 'secret');

  BitmeshClient clientWith(
    MockClientHandler handler, {
    AppCheckTokenProvider? provider,
    RetryPolicy retryPolicy = const RetryPolicy.none(),
  }) {
    return BitmeshClient(
      credentials: credentials,
      options: BitmeshOptions(
        retryPolicy: retryPolicy,
        appCheckTokenProvider: provider,
      ),
      httpClient: MockClient(handler),
    );
  }

  http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  group('App Check token', () {
    test('is sent on signed JSON, GET and multipart requests', () async {
      final captured = <http.BaseRequest>[];
      final client = clientWith(
        (request) async {
          captured.add(request);
          return jsonResponse({'id': 'j1', 'status': 'queued'});
        },
        provider: () => 'token-1',
      );

      await client.chat.createRaw({'model': 'm', 'messages': <Object>[]});
      await client.video.getRaw('j1');
      await client.transcription.create(
        BitmeshFile.fromBytes([1, 2, 3], filename: 'note.m4a'),
      );

      expect(captured, hasLength(3));
      for (final request in captured) {
        expect(request.headers['X-Firebase-AppCheck'], 'token-1',
            reason: '${request.method} ${request.url.path}');
        expect(request.headers['Authorization'], startsWith('OAuth '));
      }
    });

    test('is not part of the payload signature', () async {
      late http.Request captured;
      final client = clientWith(
        (request) async {
          captured = request;
          return jsonResponse({'ok': true});
        },
        provider: () async => 'token-1',
      );

      await client.chat.createRaw({'a': 1});

      final oauthSignature = Uri.decodeComponent(
        RegExp(r'oauth_signature="([^"]+)"')
            .firstMatch(captured.headers['Authorization']!)!
            .group(1)!,
      );
      expect(
        captured.headers['X-Payload-Signature'],
        OAuth1Signer(credentials: credentials)
            .payloadSignature(captured.body, oauthSignature),
      );
    });

    test('is not sent when no provider is set', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({'ok': true});
      });

      await client.chat.createRaw({});

      expect(captured.headers.containsKey('X-Firebase-AppCheck'), isFalse);
    });

    test('is not sent on unsigned result downloads', () async {
      late http.Request captured;
      final client = clientWith(
        (request) async {
          captured = request;
          return http.Response.bytes([1], 200);
        },
        provider: () => 'token-1',
      );

      await client.images.download('obj-1');

      expect(captured.headers.containsKey('X-Firebase-AppCheck'), isFalse);
    });

    test('overrides a default header of the same name', () async {
      late http.Request captured;
      final client = BitmeshClient(
        credentials: credentials,
        options: BitmeshOptions(
          retryPolicy: const RetryPolicy.none(),
          defaultHeaders: const {'X-Firebase-AppCheck': 'stale'},
          appCheckTokenProvider: () => 'fresh',
        ),
        httpClient: MockClient((request) async {
          captured = request;
          return jsonResponse({'ok': true});
        }),
      );

      await client.chat.createRaw({});

      expect(captured.headers['X-Firebase-AppCheck'], 'fresh');
    });

    test('is fetched again for every retry', () async {
      var calls = 0;
      final tokens = <String?>[];
      final client = clientWith(
        (request) async {
          tokens.add(request.headers['X-Firebase-AppCheck']);
          return tokens.length < 3
              ? http.Response('rate limited', 429)
              : jsonResponse({'ok': true});
        },
        provider: () => 'token-${++calls}',
        retryPolicy: const RetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
          maxDelay: Duration(milliseconds: 2),
          useJitter: false,
        ),
      );

      await client.chat.createRaw({});

      expect(tokens, ['token-1', 'token-2', 'token-3']);
    });
  });

  group('App Check failures', () {
    test('a throwing provider stops the request before it is sent', () async {
      var sent = 0;
      final failure = StateError('attestation failed');
      final client = clientWith(
        (_) async {
          sent++;
          return jsonResponse({'ok': true});
        },
        provider: () => throw failure,
        retryPolicy: const RetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
        ),
      );

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshAppCheckTokenException>()
            .having((e) => e.cause, 'cause', same(failure))),
      );
      expect(sent, 0);
    });

    test('a provider without a token stops the request', () async {
      var sent = 0;
      final client = clientWith(
        (_) async {
          sent++;
          return jsonResponse({'ok': true});
        },
        provider: () async => null,
      );

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshAppCheckTokenException>()),
      );
      expect(sent, 0);
    });

    test('API rejections map to BitmeshAppCheckRejectedException', () async {
      // Messages exactly as the API's VerifyAppCheck middleware returns them.
      const messages = [
        'Missing X-Firebase-AppCheck header',
        'App Check token is malformed',
        'App Check token signature is invalid',
        'App Check token has expired',
        'App Check token is for an unregistered app',
        'API key is not configured for App Check',
        'App Check verification is temporarily unavailable',
      ];

      for (final message in messages) {
        final client = clientWith(
          (_) async => jsonResponse({'error': message}, status: 401),
          provider: () => 'token-1',
        );

        await expectLater(
          client.chat.createRaw({}),
          throwsA(isA<BitmeshAppCheckRejectedException>()
              .having((e) => e.message, 'message', message)
              .having((e) => e.statusCode, 'statusCode', 401)),
          reason: message,
        );
      }
    });

    test('rejections are still authentication errors', () async {
      final client = clientWith(
        (_) async =>
            jsonResponse({'error': 'App Check token has expired'}, status: 401),
      );

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshAuthenticationException>()),
      );
    });

    test('only an outage on the API side counts as temporary', () async {
      Future<BitmeshAppCheckRejectedException> rejection(String message) async {
        final client = clientWith(
          (_) async => jsonResponse({'error': message}, status: 401),
        );
        try {
          await client.chat.createRaw({});
        } on BitmeshAppCheckRejectedException catch (e) {
          return e;
        }
        fail('expected a rejection for "$message"');
      }

      expect(
        (await rejection('App Check verification is temporarily unavailable'))
            .isTemporary,
        isTrue,
      );
      expect((await rejection('App Check token has expired')).isTemporary,
          isFalse);
    });

    test('other 401s stay plain authentication errors', () async {
      final client = clientWith(
        (_) async => jsonResponse({'error': 'Invalid signature'}, status: 401),
        provider: () => 'token-1',
      );

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshAuthenticationException>().having(
            (e) => e is BitmeshAppCheckRejectedException,
            'is App Check rejection',
            isFalse)),
      );
    });
  });
}
