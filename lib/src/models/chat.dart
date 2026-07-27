import 'package:meta/meta.dart';

import 'json_utils.dart';

/// Role of a chat message.
class ChatRole {
  const ChatRole._(this.value);

  final String value;

  static const ChatRole system = ChatRole._('system');
  static const ChatRole user = ChatRole._('user');
  static const ChatRole assistant = ChatRole._('assistant');
  static const ChatRole tool = ChatRole._('tool');

  /// Accepts roles this SDK does not know about yet.
  factory ChatRole.custom(String value) => ChatRole._(value);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is ChatRole && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A single message in a conversation.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.name,
  });

  const ChatMessage.system(String content) : this(role: ChatRole.system, content: content);

  const ChatMessage.user(String content, {String? name})
      : this(role: ChatRole.user, content: content, name: name);

  const ChatMessage.assistant(String content)
      : this(role: ChatRole.assistant, content: content);

  final ChatRole role;

  /// Message text. Multi-part content returned by the API is flattened to its
  /// text segments.
  final String content;

  /// Optional speaker name, supported by some models.
  final String? name;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: ChatRole.custom(asString(json['role']) ?? 'assistant'),
      content: _flattenContent(json['content']),
      name: asString(json['name']),
    );
  }

  Map<String, dynamic> toJson() => compact({
        'role': role.value,
        'content': content,
        'name': name,
      });

  ChatMessage copyWith({ChatRole? role, String? content, String? name}) =>
      ChatMessage(
        role: role ?? this.role,
        content: content ?? this.content,
        name: name ?? this.name,
      );

  @override
  String toString() => 'ChatMessage(${role.value}: $content)';

  static String _flattenContent(Object? content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      // Multimodal content: [{"type": "text", "text": "..."}, ...]
      return content
          .map((part) {
            final map = asMap(part);
            if (map == null) return asString(part) ?? '';
            return asString(pick(map, ['text', 'content'])) ?? '';
          })
          .where((s) => s.isNotEmpty)
          .join();
    }
    return content.toString();
  }
}

/// Parameters for `POST /chat`.
@immutable
class ChatRequest {
  const ChatRequest({
    required this.model,
    required this.messages,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.frequencyPenalty,
    this.repetitionPenalty,
    this.stop,
    this.test,
    this.extra = const {},
  });

  final String model;
  final List<ChatMessage> messages;

  /// Upper bound on generated tokens.
  final int? maxTokens;

  /// Randomness, 0-1. Lower is more deterministic.
  final double? temperature;

  final double? topP;

  /// -2.0 to 2.0. Discourages repeated tokens.
  final double? frequencyPenalty;

  final double? repetitionPenalty;

  /// Stop sequences.
  final List<String>? stop;

  /// When true the API returns dummy data without consuming credits.
  final bool? test;

  /// Extra fields merged into the request body, for parameters this SDK does
  /// not model yet. These win over the typed fields above.
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        ...compact({
          'model': model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'max_tokens': maxTokens,
          'temperature': temperature,
          'top_p': topP,
          'frequency_penalty': frequencyPenalty,
          'repetition_penalty': repetitionPenalty,
          'stop': stop,
          'test': test,
        }),
        ...extra,
      };

  ChatRequest copyWith({
    String? model,
    List<ChatMessage>? messages,
    int? maxTokens,
    double? temperature,
    double? topP,
    double? frequencyPenalty,
    double? repetitionPenalty,
    List<String>? stop,
    bool? test,
    Map<String, dynamic>? extra,
  }) {
    return ChatRequest(
      model: model ?? this.model,
      messages: messages ?? this.messages,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      stop: stop ?? this.stop,
      test: test ?? this.test,
      extra: extra ?? this.extra,
    );
  }
}

/// Token accounting for a completion.
@immutable
class TokenUsage {
  const TokenUsage({this.promptTokens, this.completionTokens, this.totalTokens});

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
        promptTokens: asInt(pick(json, ['prompt_tokens', 'input_tokens'])),
        completionTokens:
            asInt(pick(json, ['completion_tokens', 'output_tokens'])),
        totalTokens: asInt(pick(json, ['total_tokens'])),
      );

  @override
  String toString() => 'TokenUsage(prompt: $promptTokens, '
      'completion: $completionTokens, total: $totalTokens)';
}

/// One generated alternative.
@immutable
class ChatChoice {
  const ChatChoice({
    required this.index,
    required this.message,
    this.finishReason,
  });

  final int index;
  final ChatMessage message;
  final String? finishReason;

  factory ChatChoice.fromJson(Map<String, dynamic> json) {
    final message = asMap(pick(json, ['message', 'delta']));
    return ChatChoice(
      index: asInt(json['index']) ?? 0,
      message: message != null
          ? ChatMessage.fromJson(message)
          : ChatMessage.assistant(asString(json['text']) ?? ''),
      finishReason: asString(pick(json, ['finish_reason'])),
    );
  }

  @override
  String toString() => 'ChatChoice($index, finish: $finishReason)';
}

/// Response of `POST /chat`.
@immutable
class ChatCompletion {
  const ChatCompletion({
    required this.choices,
    required this.raw,
    this.id,
    this.model,
    this.created,
    this.usage,
  });

  final String? id;
  final String? model;
  final DateTime? created;
  final List<ChatChoice> choices;
  final TokenUsage? usage;

  /// The unmodified response body, for fields this SDK does not expose.
  final Map<String, dynamic> raw;

  factory ChatCompletion.fromJson(Map<String, dynamic> json) {
    final usage = asMap(json['usage']);
    return ChatCompletion(
      id: asString(json['id']),
      model: asString(json['model']),
      created: asDateTime(json['created']),
      choices: asMapList(json['choices'])
          .map(ChatChoice.fromJson)
          .toList(growable: false),
      usage: usage == null ? null : TokenUsage.fromJson(usage),
      raw: json,
    );
  }

  /// Content of the first choice, or `null` when the model returned nothing.
  String? get text {
    if (choices.isEmpty) return null;
    final content = choices.first.message.content;
    return content.isEmpty ? null : content;
  }

  @override
  String toString() => 'ChatCompletion(model: $model, choices: ${choices.length})';
}
