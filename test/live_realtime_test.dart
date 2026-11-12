@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:bitmesh/bitmesh.dart';
import 'package:test/test.dart';

/// Streams real audio to the live API. Skipped unless BITMESH_TEST_API_KEY (a
/// v2 hosted key) and BITMESH_TEST_AUDIO_PCM (16 kHz 16-bit mono PCM) are set.
/// Billed: a 20 s clip on universal-streaming-english costs about 0.002.
///
///   BITMESH_TEST_API_KEY=bmk_... BITMESH_TEST_AUDIO_PCM=clip.pcm \
///     dart test test/live_realtime_test.dart
void main() {
  final env = Platform.environment;
  final key = env['BITMESH_TEST_API_KEY'] ?? '';
  final audioPath = env['BITMESH_TEST_AUDIO_PCM'] ?? '';
  final skip = key.isEmpty || audioPath.isEmpty
      ? 'Set BITMESH_TEST_API_KEY and BITMESH_TEST_AUDIO_PCM'
      : null;

  test('a real-time session transcribes streamed audio', () async {
    final client = BitmeshClient(
      apiKey: key,
      options: BitmeshOptions(
        baseUrl: env['BITMESH_TEST_BASE_URL'] ?? BitmeshOptions.defaultBaseUrl,
      ),
    );
    final audio = File(audioPath).readAsBytesSync();

    final session = await client.transcription.connectRealtime(
      speechModel: env['BITMESH_TEST_SPEECH_MODEL'] ??
          RealtimeSpeechModel.universalStreamingEnglish,
      formatTurns: true,
    );
    final turns = <String>[];
    final listening = session.events.listen((event) {
      if (event is RealtimeTurn && event.endOfTurn) turns.add(event.transcript);
    });

    for (var i = 0; i < audio.length; i += 1600) {
      session.sendAudio(audio.sublist(i, (i + 1600).clamp(0, audio.length)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final termination = await session.terminate();
    await listening.asFuture<void>();
    client.close();

    print('Transcript: ${turns.join(' ')}');
    print('Termination: ${termination?.raw}');
    expect(turns.join(' '), isNotEmpty);
    expect(session.closeCode, 1000);
    expect(
        termination?.audioDurationSeconds, closeTo(audio.length / 32000, 1.5));
    expect(termination?.sessionDurationSeconds, greaterThan(0));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('a wrong key is refused before any audio', () async {
    final client = BitmeshClient(
      apiKey: 'bmk_not_a_key',
      options: BitmeshOptions(
        baseUrl: env['BITMESH_TEST_BASE_URL'] ?? BitmeshOptions.defaultBaseUrl,
      ),
    );
    await expectLater(client.transcription.connectRealtime(),
        throwsA(isA<BitmeshAuthenticationException>()));
    client.close();
  }, skip: skip);
}
