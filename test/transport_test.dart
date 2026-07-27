import 'dart:async';
import 'dart:convert';

import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final credentials = BitmeshCredentials(key: 'key', secret: 'secret');

  BitmeshClient clientWith(
    MockClientHandler handler, {
    BitmeshOptions? options,
  }) {
    return BitmeshClient(
      credentials: credentials,
      options: options ??
          const BitmeshOptions(
            retryPolicy: RetryPolicy.none(),
          ),
      httpClient: MockClient(handler),
    );
  }

  const fastRetries = RetryPolicy(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 1),
    maxDelay: Duration(milliseconds: 2),
    useJitter: false,
  );

  http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  group('signed JSON requests', () {
    test('carry both signatures and the right content type', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({'ok': true});
      });

      await client.chat.createRaw({'model': 'm', 'messages': <Object>[]});

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://api.bitmesh.ai/chat');
      expect(captured.headers['Authorization'], startsWith('OAuth '));
      expect(captured.headers['Authorization'], contains('oauth_signature='));
      expect(captured.headers['X-Payload-Signature'], hasLength(64));
      expect(captured.headers['Content-Type'], startsWith('application/json'));
      expect(captured.headers['Accept'], 'application/json');
      expect(
        jsonDecode(captured.body),
        {'model': 'm', 'messages': <Object>[]},
      );
    });

    test('payload signature covers the exact body sent', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({'ok': true});
      });

      await client.chat.createRaw({'a': 1});

      final signer = OAuth1Signer(credentials: credentials);
      final authHeader = captured.headers['Authorization']!;
      final oauthSignature = Uri.decodeComponent(
        RegExp(r'oauth_signature="([^"]+)"').firstMatch(authHeader)!.group(1)!,
      );

      expect(
        captured.headers['X-Payload-Signature'],
        signer.payloadSignature(captured.body, oauthSignature),
      );
    });

    test('GET requests sign an empty payload and send no body', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({'id': 'v1', 'status': 'completed'});
      });

      await client.video.get('v1');

      expect(captured.method, 'GET');
      expect(captured.body, isEmpty);
      expect(captured.headers['X-Payload-Signature'], hasLength(64));
      expect(captured.headers.containsKey('Content-Type'), isFalse);
    });

    test('query parameters are encoded into the signed URL', () async {
      late Uri captured;
      final client = clientWith((request) async {
        captured = request.url;
        return jsonResponse({'id': 'v1', 'status': 'completed'});
      });

      await client.video.get('v 1', query: {'include': 'outputs & cost'});

      expect(captured.path, '/video/v%201');
      expect(captured.queryParameters['include'], 'outputs & cost');
    });

    test('each attempt gets a fresh nonce', () async {
      final nonces = <String>[];
      final client = clientWith(
        (request) async {
          nonces.add(RegExp(r'oauth_nonce="([^"]+)"')
              .firstMatch(request.headers['Authorization']!)!
              .group(1)!);
          return nonces.length < 3
              ? http.Response('busy', 429)
              : jsonResponse({'ok': true});
        },
        options: const BitmeshOptions(retryPolicy: fastRetries),
      );

      await client.chat.createRaw({'a': 1});

      expect(nonces, hasLength(3));
      expect(nonces.toSet(), hasLength(3));
    });
  });

  group('multipart requests', () {
    test('flatten nested fields and attach files', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({'id': 't1', 'status': 'queued'});
      });

      await client.transcription.create(
        BitmeshFile.fromBytes([1, 2, 3], filename: 'note.m4a'),
        speechModels: ['whisper-large'],
        fields: {
          'options': {'diarize': true},
        },
      );

      final body = captured.body;
      expect(captured.headers['Content-Type'],
          startsWith('multipart/form-data; boundary='));
      expect(body, contains('name="speech_models[0]"'));
      expect(body, contains('whisper-large'));
      expect(body, contains('name="options[diarize]"'));
      expect(body, contains('name="audio"; filename="note.m4a"'));
      expect(body, contains('content-type: audio/mp4'));
      expect(captured.headers['X-Payload-Signature'], hasLength(64));
    });

    test('the signature covers unflattened fields', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({'id': 't1'});
      });

      final fields = <String, dynamic>{
        'b': 2,
        'a': {'nested': 1},
      };
      await client.tools.submit(
        '/tools/general/background-removal',
        fields: fields,
        files: [BitmeshFile.fromBytes([9], filename: 'x.png', field: 'image')],
      );

      final signer = OAuth1Signer(credentials: credentials);
      final oauthSignature = Uri.decodeComponent(RegExp(r'oauth_signature="([^"]+)"')
          .firstMatch(captured.headers['Authorization']!)!
          .group(1)!);

      expect(
        captured.headers['X-Payload-Signature'],
        signer.multipartPayloadSignature(fields, oauthSignature),
      );
    });

    test('missing local files fail before any request is sent', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return jsonResponse({});
      });

      await expectLater(
        client.transcription.createFromPath('/definitely/not/here.m4a'),
        throwsA(isA<BitmeshArgumentException>()),
      );
      expect(called, isFalse);
    });
  });

  group('error mapping', () {
    test('maps status codes to specific exception types', () async {
      Future<void> check(int status, Matcher matcher) async {
        final client = clientWith(
          (_) async => jsonResponse(
            {
              'error': {
                'message': 'boom',
                'type': 'invalid_request_error',
                'code': 'bad',
              }
            },
            status: status,
          ),
        );
        await expectLater(client.chat.createRaw({}), throwsA(matcher));
      }

      await check(400, isA<BitmeshBadRequestException>());
      await check(401, isA<BitmeshAuthenticationException>());
      await check(403, isA<BitmeshAuthenticationException>());
      await check(404, isA<BitmeshNotFoundException>());
      await check(429, isA<BitmeshRateLimitException>());
      await check(500, isA<BitmeshServerException>());
      await check(418, isA<BitmeshApiException>());
    });

    test('surfaces the API error message, type and code', () async {
      final client = clientWith(
        (_) async => jsonResponse(
          {
            'error': {
              'message': 'Insufficient credits',
              'type': 'billing',
              'code': 'no_credits',
            }
          },
          status: 402,
        ),
      );

      try {
        await client.chat.createRaw({});
        fail('should have thrown');
      } on BitmeshApiException catch (e) {
        expect(e.statusCode, 402);
        expect(e.message, 'Insufficient credits');
        expect(e.type, 'billing');
        expect(e.code, 'no_credits');
      }
    });

    test('falls back to the raw body when it is not JSON', () async {
      final client = clientWith(
        (_) async => http.Response('<html>gateway down</html>', 502),
      );

      try {
        await client.chat.createRaw({});
        fail('should have thrown');
      } on BitmeshServerException catch (e) {
        expect(e.message, contains('gateway down'));
        expect(e.body, contains('<html>'));
      }
    });

    test('reads Retry-After', () async {
      final client = clientWith(
        (_) async => http.Response('slow down', 429, headers: {
          'retry-after': '7',
        }),
      );

      try {
        await client.chat.createRaw({});
        fail('should have thrown');
      } on BitmeshRateLimitException catch (e) {
        expect(e.retryAfter, const Duration(seconds: 7));
      }
    });

    test('non-JSON success bodies raise a serialization error', () async {
      final client = clientWith((_) async => http.Response('not json', 200));

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshSerializationException>()),
      );
    });

    test('JSON arrays are rejected where an object is expected', () async {
      final client = clientWith((_) async => http.Response('[1,2]', 200));

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshSerializationException>()),
      );
    });

    test('connection failures become BitmeshNetworkException', () async {
      final client = clientWith(
        (_) async => throw http.ClientException('connection closed'),
      );

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshNetworkException>()),
      );
    });

    test('slow responses become BitmeshTimeoutException', () async {
      final client = clientWith(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return jsonResponse({});
        },
        options: const BitmeshOptions(
          timeout: Duration(milliseconds: 50),
          retryPolicy: RetryPolicy.none(),
        ),
      );

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshTimeoutException>()),
      );
    });
  });

  group('retries', () {
    test('retry 429 for writes and eventually succeed', () async {
      var attempts = 0;
      final client = clientWith(
        (_) async {
          attempts++;
          return attempts < 3
              ? http.Response('rate limited', 429)
              : jsonResponse({'ok': true});
        },
        options: const BitmeshOptions(retryPolicy: fastRetries),
      );

      expect(await client.chat.createRaw({}), {'ok': true});
      expect(attempts, 3);
    });

    test('do not retry writes on 500 by default', () async {
      var attempts = 0;
      final client = clientWith(
        (_) async {
          attempts++;
          return http.Response('server error', 500);
        },
        options: const BitmeshOptions(retryPolicy: fastRetries),
      );

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshServerException>()),
      );
      expect(attempts, 1, reason: 'a POST may have already been processed');
    });

    test('retry writes on 500 when opted in', () async {
      var attempts = 0;
      final client = clientWith(
        (_) async {
          attempts++;
          return attempts < 2
              ? http.Response('server error', 500)
              : jsonResponse({'ok': true});
        },
        options: BitmeshOptions(
          retryPolicy: fastRetries.copyWith(retryWritesOnServerError: true),
        ),
      );

      expect(await client.chat.createRaw({}), {'ok': true});
      expect(attempts, 2);
    });

    test('retry GETs on 500', () async {
      var attempts = 0;
      final client = clientWith(
        (_) async {
          attempts++;
          return attempts < 3
              ? http.Response('server error', 503)
              : jsonResponse({'id': 'v1', 'status': 'completed'});
        },
        options: const BitmeshOptions(retryPolicy: fastRetries),
      );

      final job = await client.video.get('v1');
      expect(job.isCompleted, isTrue);
      expect(attempts, 3);
    });

    test('give up after maxAttempts', () async {
      var attempts = 0;
      final client = clientWith(
        (_) async {
          attempts++;
          return http.Response('rate limited', 429);
        },
        options: const BitmeshOptions(retryPolicy: fastRetries),
      );

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshRateLimitException>()),
      );
      expect(attempts, 3);
    });

    test('retry network failures', () async {
      var attempts = 0;
      final client = clientWith(
        (_) async {
          attempts++;
          if (attempts < 3) throw http.ClientException('reset');
          return jsonResponse({'ok': true});
        },
        options: const BitmeshOptions(retryPolicy: fastRetries),
      );

      expect(await client.chat.createRaw({}), {'ok': true});
      expect(attempts, 3);
    });

    test('never retry 4xx client errors', () async {
      var attempts = 0;
      final client = clientWith(
        (_) async {
          attempts++;
          return http.Response('nope', 400);
        },
        options: const BitmeshOptions(retryPolicy: fastRetries),
      );

      await expectLater(
        client.chat.createRaw({}),
        throwsA(isA<BitmeshBadRequestException>()),
      );
      expect(attempts, 1);
    });
  });

  group('configuration', () {
    test('honours a custom base URL', () async {
      late Uri captured;
      final client = clientWith(
        (request) async {
          captured = request.url;
          return jsonResponse({'ok': true});
        },
        options: const BitmeshOptions(
          baseUrl: 'https://staging.example.com/api/',
          retryPolicy: RetryPolicy.none(),
        ),
      );

      await client.chat.createRaw({});
      expect(captured.toString(), 'https://staging.example.com/api/chat');
    });

    test('rejects a malformed base URL', () {
      expect(
        () => BitmeshClient(
          credentials: credentials,
          options: const BitmeshOptions(baseUrl: 'not-a-url'),
        ),
        throwsA(isA<BitmeshConfigurationException>()),
      );
    });

    test('merges default headers without letting them break signing', () async {
      late http.Request captured;
      final client = clientWith(
        (request) async {
          captured = request;
          return jsonResponse({'ok': true});
        },
        options: const BitmeshOptions(
          defaultHeaders: {'X-App': 'spender', 'Authorization': 'hijack'},
          userAgent: 'spender/1.0',
          retryPolicy: RetryPolicy.none(),
        ),
      );

      await client.chat.createRaw({});
      expect(captured.headers['X-App'], 'spender');
      expect(captured.headers['User-Agent'], 'spender/1.0');
      expect(captured.headers['Authorization'], startsWith('OAuth '));
    });

    test('an injected http client is not closed by close()', () async {
      final inner = MockClient((_) async => jsonResponse({'ok': true}));
      final client = BitmeshClient(credentials: credentials, httpClient: inner);

      client.close();
      // Would throw if the client had been closed.
      expect(await inner.get(Uri.parse('https://api.bitmesh.ai/ping')),
          isA<http.Response>());
    });

    test('logs retries and failures without leaking credentials', () async {
      final messages = <String>[];
      final client = clientWith(
        (_) async => http.Response('rate limited', 429),
        options: BitmeshOptions(
          retryPolicy: fastRetries,
          logger: CallbackBitmeshLogger(messages.add),
        ),
      );

      await expectLater(client.chat.createRaw({}), throwsA(isA<BitmeshApiException>()));

      expect(messages.where((m) => m.contains('Retrying')), hasLength(2));
      expect(messages.any((m) => m.contains('secret')), isFalse);
    });
  });

  group('unsigned result fetching', () {
    test('image results are fetched without an Authorization header', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return http.Response.bytes([1, 2, 3], 200);
      });

      final bytes = await client.images.download('obj-1');

      expect(bytes, [1, 2, 3]);
      expect(captured.url.path, '/imgrslt/obj-1');
      expect(captured.headers.containsKey('Authorization'), isFalse);
    });

    test('result URLs are built from the base URL', () {
      final client = clientWith((_) async => jsonResponse({}));
      expect(client.images.resultUrl('abc'),
          'https://api.bitmesh.ai/imgrslt/abc');
    });
  });
}
