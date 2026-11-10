// Chat payloads as API v2 returns them: OpenAI's snake_case for every model,
// streamed or not.
import 'dart:convert';

import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';
import 'package:test/test.dart';

/// `POST /v2/chat`, `model: bitmeshai/chat-now-nano`.
const _chatResponse = '''
{
  "id": "chatcmpl-E6Cu05PrJHfC3dGf8ZPoNtk4i6xWg",
  "object": "chat.completion",
  "created": 1785148272,
  "model": "gpt-5-nano-2025-08-07",
  "system_fingerprint": null,
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "OK",
        "annotations": [],
        "tool_calls": []
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 11,
    "completion_tokens": 74,
    "total_tokens": 85,
    "completion_tokens_details": {"reasoning_tokens": 64}
  }
}
''';

/// `max_tokens` too small for a reasoning model: the budget is spent on
/// reasoning tokens and `content` comes back empty.
const _truncatedChatResponse = '''
{
  "id": "chatcmpl-E6Cu2ivZoH0HBoehaVRc0VKpPH7D9",
  "object": "chat.completion",
  "created": 1785148274,
  "model": "gpt-5-nano-2025-08-07",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": ""},
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 11,
    "completion_tokens": 10,
    "total_tokens": 21,
    "completion_tokens_details": {"reasoning_tokens": 10}
  }
}
''';

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

void main() {
  group('chat response', () {
    final completion = ChatCompletion.fromJson(_decode(_chatResponse));

    test('extracts the assistant content', () {
      expect(completion.text, 'OK');
    });

    test('parses finish_reason and usage', () {
      expect(completion.choices.single.finishReason, 'stop');
      expect(completion.usage?.promptTokens, 11);
      expect(completion.usage?.completionTokens, 74);
      expect(completion.usage?.totalTokens, 85);
    });

    test('reports the resolved upstream model, not the alias requested', () {
      expect(completion.model, 'gpt-5-nano-2025-08-07');
      expect(completion.created, isNotNull);
    });
  });

  group('truncated response', () {
    final completion = ChatCompletion.fromJson(_decode(_truncatedChatResponse));

    test('text is null and finishReason explains why', () {
      expect(completion.text, isNull);
      expect(completion.choices.single.finishReason, 'length');
    });

    test('reasoning tokens consumed the whole budget', () {
      expect(completion.usage?.completionTokens, 10);
      final usage = completion.raw['usage'] as Map<String, dynamic>;
      final details =
          usage['completion_tokens_details'] as Map<String, dynamic>;
      expect(details['reasoning_tokens'], 10);
    });
  });

  group('streamed chunks', () {
    test('a text chunk', () {
      final chunk = ChatChunk.fromJson(_decode(
        '{"id":"chatcmpl-9x2","object":"chat.completion.chunk",'
        '"choices":[{"index":0,"delta":{"content":"There"}}]}',
      ));
      expect(chunk.text, 'There');
      expect(chunk.usage, isNull);
    });

    test('the closing usage chunk has no choices', () {
      final chunk = ChatChunk.fromJson(_decode(
        '{"id":"chatcmpl-9x2","choices":[],'
        '"usage":{"prompt_tokens":51,"completion_tokens":4,"total_tokens":55}}',
      ));
      expect(chunk.text, '');
      expect(chunk.finishReason, isNull);
      expect(chunk.usage?.totalTokens, 55);
    });
  });
}
