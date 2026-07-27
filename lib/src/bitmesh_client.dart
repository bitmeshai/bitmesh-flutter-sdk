import 'package:http/http.dart' as http;

import 'api/chat_api.dart';
import 'api/image_api.dart';
import 'api/tools_api.dart';
import 'api/transcription_api.dart';
import 'api/video_api.dart';
import 'auth/oauth1_signer.dart';
import 'bitmesh_credentials.dart';
import 'bitmesh_options.dart';
import 'http/bitmesh_transport.dart';

/// Entry point of the SDK.
///
/// ```dart
/// final client = BitmeshClient.fromKeys(key, secret);
/// final answer = await client.chat.prompt('Hi', model: 'bitmeshai/chat-now-nano');
/// client.close();
/// ```
///
/// One client can serve the whole app: it is safe to use concurrently and keeps
/// a connection pool alive. Call [close] when you are done with it (or never,
/// if it lives as long as the app).
class BitmeshClient {
  /// Creates a client from a credentials object.
  ///
  /// Pass [httpClient] to reuse an existing connection pool, to install
  /// interceptors, or to inject a mock in tests. An injected client is not
  /// closed by [close].
  BitmeshClient({
    required BitmeshCredentials credentials,
    BitmeshOptions options = const BitmeshOptions(),
    http.Client? httpClient,
  })  : _options = options,
        _transport = BitmeshTransport(
          signer: OAuth1Signer(credentials: credentials),
          options: options,
          httpClient: httpClient,
        ) {
    chat = ChatApi(_transport);
    images = ImageApi(_transport, options.baseUrl);
    video = VideoApi(_transport);
    transcription = TranscriptionApi(_transport);
    tools = ToolsApi(_transport);
  }

  /// Creates a client straight from a key/secret pair.
  factory BitmeshClient.fromKeys(
    String key,
    String secret, {
    BitmeshOptions options = const BitmeshOptions(),
    http.Client? httpClient,
  }) {
    return BitmeshClient(
      credentials: BitmeshCredentials(key: key, secret: secret),
      options: options,
      httpClient: httpClient,
    );
  }

  final BitmeshOptions _options;
  final BitmeshTransport _transport;

  /// Chat completions. Callable: `client.chat({...})` sends a raw payload.
  late final ChatApi chat;

  /// Image generation. Callable: `client.images({...})`.
  late final ImageApi images;

  /// Video generation and job polling. Callable: `client.video({...})`.
  late final VideoApi video;

  /// Audio transcription and job polling.
  late final TranscriptionApi transcription;

  /// `/tools` endpoints and async task polling.
  late final ToolsApi tools;

  /// Alias for [images], matching the `/image` endpoint name.
  ImageApi get image => images;

  /// The configuration this client was built with.
  BitmeshOptions get options => _options;

  /// Escape hatch for endpoints this SDK does not wrap yet.
  BitmeshTransport get transport => _transport;

  /// Releases the underlying connections.
  ///
  /// Does nothing to an `http.Client` you injected yourself.
  void close() => _transport.close();
}
