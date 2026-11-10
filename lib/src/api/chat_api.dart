import 'dart:convert';

import '../exceptions.dart';
import '../http/bitmesh_transport.dart';
import '../models/chat.dart';

/// `POST /v2/chat`: chat completions, whole or streamed.
class ChatApi {
  ChatApi(this._transport);

  final BitmeshTransport _transport;

  /// Typed chat completion.
  Future<ChatCompletion> create(ChatRequest request) async {
    final json = await _transport.postJson('/chat', request.toJson());
    return ChatCompletion.fromJson(json);
  }

  /// Streams the reply while the model writes it.
  ///
  /// Each [ChatChunk] carries the new text in [ChatChunk.text]; the last one
  /// carries [ChatChunk.usage]. The request is billed once, when the stream
  /// ends. Cancel the subscription to stop generating: you pay only for what
  /// was written.
  ///
  /// ```dart
  /// await for (final chunk in client.chat.stream(request)) {
  ///   reply.write(chunk.text);
  /// }
  /// ```
  Stream<ChatChunk> stream(ChatRequest request) async* {
    final events = _transport.stream(
      'POST',
      '/chat',
      body: jsonEncode({...request.toJson(), 'stream': true}),
    );
    await for (final event in events) {
      if (event.isDone) return;
      final json = event.json();
      if (json['error'] != null) {
        // The provider failed after the reply had started.
        throw BitmeshApiException.fromResponse(502, event.data);
      }
      yield ChatChunk.fromJson(json);
    }
  }

  /// Streams the reply and returns it whole once finished, calling [onText]
  /// with each new piece of text.
  Future<String> streamText(
    ChatRequest request, {
    void Function(String text)? onText,
  }) async {
    final reply = StringBuffer();
    await for (final chunk in stream(request)) {
      if (chunk.text.isEmpty) continue;
      reply.write(chunk.text);
      onText?.call(chunk.text);
    }
    return reply.toString();
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
}
