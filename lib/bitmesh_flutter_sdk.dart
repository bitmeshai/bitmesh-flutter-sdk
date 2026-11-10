/// A Dart & Flutter SDK for the [Bitmesh](https://bitmesh.ai) AI API v2.
///
/// Sends your `bmk_` key as a bearer token, plus the Firebase App Check token
/// on mobile keys, and exposes chat (streaming included), image, video,
/// transcription, tools and the provider proxy as typed calls with retries
/// and job polling built in.
///
/// ```dart
/// final client = BitmeshClient(apiKey: 'bmk_...');
///
/// final completion = await client.chat.create(ChatRequest(
///   model: 'bitmeshai/chat-now-nano',
///   messages: [ChatMessage.user('Summarise this receipt: ...')],
/// ));
/// print(completion.text);
/// ```
///
/// The package has no Flutter dependency, so it also runs in plain Dart
/// (server, CLI, tests). Path-based uploads need `dart:io`; on the web use
/// [BitmeshFile.fromBytes].
library;

export 'src/api/chat_api.dart';
export 'src/api/image_api.dart';
export 'src/api/proxy_api.dart';
export 'src/api/tools_api.dart';
export 'src/api/transcription_api.dart';
export 'src/api/video_api.dart';
export 'src/bitmesh_client.dart';
export 'src/bitmesh_file.dart';
export 'src/bitmesh_options.dart';
export 'src/exceptions.dart';
export 'src/http/bitmesh_transport.dart' show BitmeshResponse, BitmeshTransport;
export 'src/http/retry_policy.dart';
export 'src/http/server_sent_events.dart' show ServerSentEvent;
export 'src/logging.dart';
export 'src/models/chat.dart';
export 'src/models/image.dart';
export 'src/models/job_status.dart';
export 'src/models/transcription.dart';
export 'src/models/tools.dart';
export 'src/models/video.dart';
export 'src/polling.dart';
