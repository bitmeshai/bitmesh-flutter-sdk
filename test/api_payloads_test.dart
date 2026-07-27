// Payloads captured verbatim from api.bitmesh.ai on 2026-07-27.
//
// The live API answers real requests in camelCase (`finishReason`,
// `promptTokens`) but the published docs — and the `test: true` debug path —
// use snake_case. Parsing must handle both, so both are pinned here.
import 'dart:convert';

import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';
// Internal helper: the casing fallback is an implementation detail, but it is
// the exact thing that broke against the live API, so it is tested directly.
import 'package:bitmesh_flutter_sdk/src/models/json_utils.dart';
import 'package:test/test.dart';

/// Real `POST /chat` response, `model: bitmeshai/chat-now-nano`.
const _realChatResponse = '''
{
  "id": "chatcmpl-E6Cu05PrJHfC3dGf8ZPoNtk4i6xWg",
  "object": "chat.completion",
  "created": 1785148272,
  "model": "gpt-5-nano-2025-08-07",
  "systemFingerprint": null,
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "OK",
        "annotations": [],
        "toolCalls": [],
        "functionCall": null,
        "audio": null,
        "images": null
      },
      "logprobs": null,
      "finishReason": "stop"
    }
  ],
  "usage": {
    "promptTokens": 11,
    "completionTokens": 74,
    "totalTokens": 85,
    "promptTokensDetails": {"audioTokens": 0, "cachedTokens": 0},
    "completionTokensDetails": {
      "audioTokens": 0,
      "reasoningTokens": 64,
      "acceptedPredictionTokens": 0,
      "rejectedPredictionTokens": 0
    }
  }
}
''';

/// Real response when `max_tokens` is too small for a reasoning model: the
/// budget is spent on reasoning tokens and `content` comes back empty.
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
      "logprobs": null,
      "finishReason": "length"
    }
  ],
  "usage": {
    "promptTokens": 11,
    "completionTokens": 10,
    "totalTokens": 21,
    "completionTokensDetails": {"reasoningTokens": 10}
  }
}
''';

/// Real response from the `test: true` debug path — snake_case.
const _debugChatResponse = '''
{
  "id": "chatcmpl-debug-6a67337572bf8",
  "object": "chat.completion",
  "created": 1785148277,
  "model": "gpt-5-nano",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": "DEBUG MODE ACTIVE"},
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 53,
    "completion_tokens": 429,
    "total_tokens": 482
  }
}
''';

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

void main() {
  group('real camelCase chat response', () {
    final completion = ChatCompletion.fromJson(_decode(_realChatResponse));

    test('extracts the assistant content', () {
      expect(completion.text, 'OK');
      expect(completion.choices.single.message.role, ChatRole.assistant);
    });

    test('parses camelCase finishReason', () {
      expect(completion.choices.single.finishReason, 'stop');
    });

    test('parses camelCase usage counters', () {
      expect(completion.usage?.promptTokens, 11);
      expect(completion.usage?.completionTokens, 74);
      expect(completion.usage?.totalTokens, 85);
    });

    test('reports the resolved upstream model, not the alias requested', () {
      expect(completion.model, 'gpt-5-nano-2025-08-07');
      expect(completion.id, startsWith('chatcmpl-'));
      expect(completion.created, DateTime.utc(2026, 7, 27, 10, 31, 12));
    });

    test('a null systemFingerprint does not break parsing', () {
      expect(completion.raw['systemFingerprint'], isNull);
    });
  });

  group('snake_case debug response', () {
    final completion = ChatCompletion.fromJson(_decode(_debugChatResponse));

    test('parses identically to the camelCase form', () {
      expect(completion.text, 'DEBUG MODE ACTIVE');
      expect(completion.choices.single.finishReason, 'stop');
      expect(completion.usage?.promptTokens, 53);
      expect(completion.usage?.completionTokens, 429);
      expect(completion.usage?.totalTokens, 482);
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
          usage['completionTokensDetails'] as Map<String, dynamic>;
      expect(details['reasoningTokens'], 10);
    });
  });

  group('key-casing fallback', () {
    test('maps snake_case to camelCase and back', () {
      expect(caseVariants('finish_reason'), ['finishReason']);
      expect(caseVariants('prompt_tokens_details'), ['promptTokensDetails']);
      expect(caseVariants('finishReason'), ['finish_reason']);
      expect(caseVariants('videoUrl'), ['video_url']);
    });

    test('single-word keys have no variants', () {
      expect(caseVariants('status'), isEmpty);
      expect(caseVariants('id'), isEmpty);
    });

    test('an exact match always wins over a variant', () {
      final json = <String, dynamic>{
        'finish_reason': 'exact',
        'finishReason': 'variant',
      };
      expect(pick(json, ['finish_reason']), 'exact');
    });
  });

  group('job models tolerate either casing', () {
    test('video job with camelCase keys', () {
      final job = VideoJob.fromJson(_decode('''
        {
          "id": "vid-1",
          "status": "completed",
          "createdAt": "2026-07-27T10:00:00Z",
          "outputs": {"videoUrl": "https://api.bitmesh.ai/imgrslt/xyz"}
        }
      '''));

      expect(job.videoUrl, 'https://api.bitmesh.ai/imgrslt/xyz');
      expect(job.createdAt, isNotNull);
    });

    test('transcription job with camelCase keys', () {
      final job = TranscriptionJob.fromJson(_decode('''
        {
          "id": "tr-1",
          "status": "completed",
          "text": "one large coffee",
          "languageCode": "en",
          "speechModels": ["whisper-large"]
        }
      '''));

      expect(job.language, 'en');
      expect(job.speechModels, ['whisper-large']);
    });

    test('tool task with camelCase keys', () {
      final task = ToolTask.fromJson(_decode('''
        {"taskId": "task-9", "status": "processing"}
      '''));

      expect(task.taskId, 'task-9');
      expect(task.status, JobStatus.inProgress);
    });
  });
}
