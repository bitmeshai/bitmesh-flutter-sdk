@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bitmesh/bitmesh.dart';
import 'package:test/test.dart';

/// A stand-in for `/v2/transcribe-realtime`: [refuse] answers the handshake
/// with an HTTP error, otherwise [onSocket] runs the session.
class FakeRealtimeServer {
  late HttpServer _server;
  final requests = <HttpRequest>[];
  final received = <Object>[];
  (int, String)? refuse;
  Future<void> Function(WebSocket socket)? onSocket;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      requests.add(request);
      final refusal = refuse;
      if (refusal != null) {
        request.response
          ..statusCode = refusal.$1
          ..headers.contentType = ContentType.json
          ..write(refusal.$2);
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      await onSocket?.call(socket);
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeRealtimeServer server;
  late BitmeshClient client;

  setUp(() async {
    server = FakeRealtimeServer();
    await server.start();
    client = BitmeshClient(
      apiKey: 'bmk_test',
      options: BitmeshOptions(baseUrl: server.baseUrl, debugToken: 'bmdbg_x'),
    );
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  test('connects with the key and settings, streams audio, ends on Terminate',
      () async {
    server.onSocket = (socket) async {
      socket.add(jsonEncode({
        'type': 'Begin',
        'id': 'sess_1',
        'expires_at': 1794471255,
      }));
      await for (final message in socket) {
        server.received.add(message as Object);
        if (message is String &&
            (jsonDecode(message) as Map)['type'] == 'Terminate') {
          socket.add(jsonEncode({
            'type': 'Turn',
            'turn_order': 0,
            'end_of_turn': false,
            'transcript': 'Smoke from',
          }));
          socket.add(jsonEncode({
            'type': 'Turn',
            'turn_order': 0,
            'end_of_turn': true,
            'turn_is_formatted': true,
            'transcript': 'Smoke from hundreds of wildfires.',
            'language_code': 'en',
            'language_confidence': 0.98,
            'words': [
              {'text': 'Smoke', 'start': 0, 'end': 300},
            ],
          }));
          socket.add(jsonEncode({
            'type': 'Termination',
            'audio_duration_seconds': 2,
            'session_duration_seconds': 3,
          }));
          await socket.close(1000);
        }
      }
    };

    final session = await client.transcription.connectRealtime(
      sampleRate: 16000,
      speechModel: RealtimeSpeechModel.universalStreamingEnglish,
      formatTurns: true,
      query: {'end_of_turn_confidence_threshold': '0.7'},
    );

    final request = server.requests.single;
    expect(request.uri.path, '/v2/transcribe-realtime');
    expect(request.uri.queryParameters, {
      'sample_rate': '16000',
      'speech_model': 'universal-streaming-english',
      'format_turns': 'true',
      'end_of_turn_confidence_threshold': '0.7',
    });
    expect(request.headers.value('authorization'), 'Bearer bmk_test');
    expect(request.headers.value('x-bitmesh-debug-token'), 'bmdbg_x');

    final events = <RealtimeEvent>[];
    final listening = session.events.listen(events.add);

    final begin = await session.begun;
    expect(begin.id, 'sess_1');
    expect(begin.expiresAt, DateTime.utc(2026, 11, 12, 8, 14, 15));

    session.sendAudio(List<int>.filled(1600, 1));
    session.sendAudio(List<int>.filled(1600, 2));
    final termination = await session.terminate();
    await listening.asFuture<void>();

    expect(termination?.sessionDurationSeconds, 3);
    expect(termination?.audioDurationSeconds, 2);
    expect(session.isClosed, isTrue);
    expect(session.closeCode, 1000);

    expect(server.received, hasLength(3));
    expect(server.received[0], List<int>.filled(1600, 1));
    expect(server.received[1], List<int>.filled(1600, 2));
    expect(jsonDecode(server.received[2] as String), {'type': 'Terminate'});

    expect(events.map((e) => e.type), ['Begin', 'Turn', 'Turn', 'Termination']);
    final last = events[2] as RealtimeTurn;
    expect(last.endOfTurn, isTrue);
    expect(last.isFormatted, isTrue);
    expect(last.transcript, 'Smoke from hundreds of wildfires.');
    expect(last.languageCode, 'en');
    expect(last.languageConfidence, 0.98);
    expect(last.words.single['text'], 'Smoke');

    expect(() => session.sendAudio([0, 0]), throwsStateError);
  });

  test('a refused handshake throws the API error before any audio', () async {
    server.refuse = (
      402,
      '{"error":"Insufficient balance","message":"The balance does not cover a minute of this model."}',
    );

    await expectLater(
      client.transcription.connectRealtime(),
      throwsA(isA<BitmeshInsufficientBalanceException>()
          .having((e) => e.statusCode, 'statusCode', 402)
          .having((e) => e.message, 'message',
              'The balance does not cover a minute of this model.')),
    );

    server.refuse = (
      422,
      '{"error":"Unsupported speech_model","message":"speech_model \\"nano\\" is not offered for real-time transcription."}',
    );
    await expectLater(
      client.transcription.connectRealtime(speechModel: 'nano'),
      throwsA(isA<BitmeshBadRequestException>()),
    );

    server.refuse = (429, '{"error":"Too many sessions open"}');
    await expectLater(
      client.transcription.connectRealtime(),
      throwsA(isA<BitmeshRateLimitException>()),
    );
  });

  test('a session closed at its time limit reports 3008 after Termination',
      () async {
    server.onSocket = (socket) async {
      socket.add(jsonEncode({'type': 'Begin', 'id': 's'}));
      socket.add(jsonEncode({
        'type': 'Termination',
        'audio_duration_seconds': 60,
        'session_duration_seconds': 60,
      }));
      await socket.close(3008, 'Session reached its time limit');
    };

    final session = await client.transcription.connectRealtime();
    final types = <String>[];
    Object? error;
    await session.events
        .handleError((Object e) => error = e)
        .forEach((e) => types.add(e.type));

    expect(types, ['Begin', 'Termination']);
    expect(
        error,
        isA<BitmeshRealtimeClosedException>()
            .having((e) => e.code, 'code', 3008)
            .having((e) => e.isTimeLimit, 'isTimeLimit', isTrue)
            .having(
                (e) => e.message, 'message', 'Session reached its time limit'));
    expect((await session.done)?.sessionDurationSeconds, 60);
  });

  test('forceEndpoint and sendMessage send JSON text messages', () async {
    final got = Completer<List<Object>>();
    server.onSocket = (socket) async {
      final messages = <Object>[];
      await for (final message in socket) {
        messages.add(message as Object);
        if (messages.length == 2) {
          await socket.close(1000);
        }
      }
      got.complete(messages);
    };

    final session = await client.transcription.connectRealtime();
    session.forceEndpoint();
    session
        .sendMessage({'type': 'UpdateConfiguration', 'max_turn_silence': 500});

    final messages = await got.future;
    expect(messages.map((m) => jsonDecode(m as String)), [
      {'type': 'ForceEndpoint'},
      {'type': 'UpdateConfiguration', 'max_turn_silence': 500},
    ]);
    expect(await session.done, isNull);
  });

  test('close() ends the session without waiting for Termination', () async {
    server.onSocket = (socket) async {
      socket.add(jsonEncode({'type': 'Begin', 'id': 's'}));
      await socket.drain<void>();
    };

    final session = await client.transcription.connectRealtime();
    await session.begun;
    await session.close();
    expect(session.isClosed, isTrue);
    expect(session.closeCode, 1000);
  });

  test('sampleRate must be positive', () {
    expect(() => client.transcription.connectRealtime(sampleRate: 0),
        throwsA(isA<BitmeshArgumentException>()));
  });

  test('unknown message types are kept as RealtimeOtherEvent', () {
    final event = RealtimeEvent.fromJson({'type': 'SpeechStarted', 'x': 1});
    expect(event, isA<RealtimeOtherEvent>());
    expect(event.type, 'SpeechStarted');
    expect(event.raw['x'], 1);
  });
}
