/// A Dart & Flutter SDK for the [Bitmesh](https://bitmesh.ai) AI API.
///
/// Handles the OAuth 1.0a request signing the API requires, and exposes chat,
/// image, video, transcription and tools endpoints as typed calls with retries
/// and job polling built in.
///
/// ```dart
/// final client = BitmeshClient.fromKeys(key, secret);
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
export 'src/api/tools_api.dart';
export 'src/api/transcription_api.dart';
export 'src/api/video_api.dart';
export 'src/auth/oauth1_signer.dart';
export 'src/bitmesh_client.dart';
export 'src/bitmesh_credentials.dart';
export 'src/bitmesh_file.dart';
export 'src/bitmesh_options.dart';
export 'src/compat.dart';
export 'src/exceptions.dart';
export 'src/http/bitmesh_transport.dart' show BitmeshResponse, BitmeshTransport;
export 'src/http/retry_policy.dart';
export 'src/logging.dart';
export 'src/models/chat.dart';
export 'src/models/image.dart';
export 'src/models/job_status.dart';
export 'src/models/transcription.dart';
export 'src/models/tools.dart';
export 'src/models/video.dart';
export 'src/polling.dart';
