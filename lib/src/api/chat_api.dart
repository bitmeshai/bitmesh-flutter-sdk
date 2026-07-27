import '../http/bitmesh_transport.dart';
import '../models/chat.dart';

/// `POST /chat` — chat completions.
///
/// The instance is callable, so the raw map form reads naturally:
///
/// ```dart
/// final json = await client.chat({'model': 'm', 'messages': [...]});
/// ```
class ChatApi {
  ChatApi(this._transport);

  final BitmeshTransport _transport;

  /// Typed chat completion.
  Future<ChatCompletion> create(ChatRequest request) async {
    final json = await _transport.postJson('/chat', request.toJson());
    return ChatCompletion.fromJson(json);
  }

  /// Convenience wrapper around [create] for single-turn prompts.
  Future<ChatCompletion> prompt(
    String prompt, {
    required String model,
    String? system,
    int? maxTokens,
    double? temperature,
    Map<String, dynamic> extra = const {},
  }) {
    return create(ChatRequest(
      model: model,
      messages: [
        if (system != null) ChatMessage.system(system),
        ChatMessage.user(prompt),
      ],
      maxTokens: maxTokens,
      temperature: temperature,
      extra: extra,
    ));
  }

  /// Raw request/response, for parameters this SDK does not model yet.
  Future<Map<String, dynamic>> createRaw(Map<String, dynamic> payload) =>
      _transport.postJson('/chat', payload);

  /// Alias for [createRaw], so `client.chat({...})` works.
  Future<Map<String, dynamic>> call(Map<String, dynamic> payload) =>
      createRaw(payload);
}
