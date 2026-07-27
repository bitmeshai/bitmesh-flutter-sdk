// Runnable end-to-end tour of the SDK.
//
//   dart run example/main.dart --key=... --secret=...
//
// Pass --video / --transcribe=<path> to exercise the long-running endpoints.
import 'dart:io';

import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final key = options['key'];
  final secret = options['secret'];

  if (key == null || secret == null) {
    stderr.writeln('Usage: dart run example/main.dart --key=... --secret=...');
    exitCode = 64;
    return;
  }

  final client = BitmeshClient.fromKeys(
    key,
    secret,
    options: const BitmeshOptions(
      timeout: Duration(seconds: 45),
      logger: ConsoleBitmeshLogger(minimumLevel: BitmeshLogLevel.warning),
    ),
  );

  try {
    await _chat(client);
    if (options.containsKey('image')) await _image(client);
    if (options.containsKey('video')) await _video(client);
    final audioPath = options['transcribe'];
    if (audioPath != null) await _transcribe(client, audioPath);
  } on BitmeshAuthenticationException catch (e) {
    stderr.writeln('Credentials rejected: ${e.message}');
    exitCode = 77;
  } on BitmeshApiException catch (e) {
    stderr.writeln('API error ${e.statusCode}: ${e.message}');
    exitCode = 1;
  } on BitmeshNetworkException catch (e) {
    stderr.writeln('Network problem: ${e.message}');
    exitCode = 69;
  } finally {
    client.close();
  }
}

Future<void> _chat(BitmeshClient client) async {
  stdout.writeln('\n== chat ==');

  final completion = await client.chat.create(const ChatRequest(
    model: 'bitmeshai/chat-now-nano',
    messages: [
      ChatMessage.system('Answer with a single short sentence.'),
      ChatMessage.user('What is a Dart isolate?'),
    ],
    maxTokens: 120,
    temperature: 0.2,
  ));

  stdout.writeln(completion.text ?? '(no content)');
  stdout.writeln('tokens: ${completion.usage?.totalTokens ?? '?'}');
}

Future<void> _image(BitmeshClient client) async {
  stdout.writeln('\n== image ==');

  final response = await client.images.generate(const ImageRequest(
    prompt: 'a watercolour fox reading a book',
    model: 'bitmeshai/image-now',
    width: 768,
    height: 768,
  ));

  for (final image in response.images) {
    stdout.writeln(image.resolveUrl(client.options.baseUrl) ?? '(no url)');
  }
}

Future<void> _video(BitmeshClient client) async {
  stdout.writeln('\n== video ==');

  final job = await client.video.generate(
    const VideoRequest(
      prompt: 'a paper plane gliding over a city at dusk',
      model: 'bitmeshai/video-now',
      seconds: '5',
      outputFormat: 'MP4',
    ),
    polling: const PollingOptions(
      interval: Duration(seconds: 5),
      backoffFactor: 1.5,
      timeout: Duration(minutes: 15),
    ),
    onUpdate: (job) => stdout.writeln('  status: ${job.rawStatus}'),
  );

  stdout.writeln('video: ${job.videoUrl}');
}

Future<void> _transcribe(BitmeshClient client, String path) async {
  stdout.writeln('\n== transcribe ==');

  final job = await client.transcription.transcribe(
    BitmeshFile.fromPath(path),
    polling: const PollingOptions(interval: Duration(seconds: 2)),
    onUpdate: (job) => stdout.writeln('  status: ${job.rawStatus}'),
  );

  stdout.writeln('transcript: ${job.text}');
}

Map<String, String> _parseArgs(List<String> args) {
  final result = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final parts = arg.substring(2).split('=');
    result[parts.first] = parts.length > 1 ? parts.sublist(1).join('=') : '';
  }
  return result;
}
