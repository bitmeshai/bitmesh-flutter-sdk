import 'package:http/http.dart' as http;

import 'api/chat_api.dart';
import 'api/image_api.dart';
import 'api/proxy_api.dart';
import 'api/tools_api.dart';
import 'api/transcription_api.dart';
import 'api/video_api.dart';
import 'bitmesh_options.dart';
import 'exceptions.dart';
import 'http/bitmesh_transport.dart';
import 'models/json_utils.dart';

/// Entry point of the SDK, for the Bitmesh API v2.
///
/// ```dart
/// final client = BitmeshClient(apiKey: 'bmk_...');
/// final answer = await client.chat.prompt('Hi', model: 'bitmeshai/chat-now-nano');
/// client.close();
/// ```
///
/// One client can serve the whole app: it is safe to use concurrently and keeps
/// a connection pool alive. Call [close] when you are done with it (or never,
/// if it lives as long as the app).
class BitmeshClient {
  /// Creates a client for a v2 key (`bmk_...`), hosted or proxy.
  ///
  /// Pass [httpClient] to reuse an existing connection pool, to install
  /// interceptors, or to inject a mock in tests. An injected client is not
  /// closed by [close].
  BitmeshClient({
    required String apiKey,
    BitmeshOptions options = const BitmeshOptions(),
    http.Client? httpClient,
  })  : _options = options,
        _transport = BitmeshTransport(
          apiKey: _checkKey(apiKey),
          options: options,
          httpClient: httpClient,
        ) {
    chat = ChatApi(_transport);
    images = ImageApi(_transport, options.baseUrl);
    video = VideoApi(_transport);
    transcription = TranscriptionApi(_transport);
    tools = ToolsApi(_transport);
    proxy = ProxyApi(_transport);
  }

  final BitmeshOptions _options;
  final BitmeshTransport _transport;

  /// Chat completions, whole or streamed.
  late final ChatApi chat;

  /// Image generation.
  late final ImageApi images;

  /// Video generation and job polling.
  late final VideoApi video;

  /// Audio transcription and job polling.
  late final TranscriptionApi transcription;

  /// `/tools` endpoints and async task polling.
  late final ToolsApi tools;

  /// The provider proxy, for proxy keys: `/v2/proxy/{provider}/{path}`.
  late final ProxyApi proxy;

  /// The configuration this client was built with.
  BitmeshOptions get options => _options;

  /// Escape hatch for endpoints this SDK does not wrap yet.
  BitmeshTransport get transport => _transport;

  /// `GET /v2/balance`: the account's credit balance.
  Future<double> balance() async {
    final json = await _transport.getJson('/balance');
    return asDouble(json['balance']) ?? 0;
  }

  /// `GET /v2/test`: succeeds when the key (and, on a mobile key, the App
  /// Check or debug token) is accepted. Throws otherwise.
  Future<void> verify() => _transport.getJson('/test');

  /// Releases the underlying connections.
  ///
  /// Does nothing to an `http.Client` you injected yourself.
  void close() => _transport.close();

  static String _checkKey(String apiKey) {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const BitmeshConfigurationException(
        'The Bitmesh API key is empty. Check that your remote config or '
        'environment value is published.',
      );
    }
    if (!key.startsWith('bmk_')) {
      throw const BitmeshConfigurationException(
        'Bitmesh API v2 keys start with "bmk_". A v1 consumer key and secret '
        'is not supported by this SDK; create a v2 key in the dashboard.',
      );
    }
    return key;
  }
}
