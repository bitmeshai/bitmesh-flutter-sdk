import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('ChatRequest', () {
    test('omits unset optional fields', () {
      final json = const ChatRequest(
        model: 'bitmeshai/chat-now-nano',
        messages: [ChatMessage.user('hi')],
      ).toJson();

      expect(json.keys, containsAll(['model', 'messages']));
      expect(json.containsKey('temperature'), isFalse);
      expect(json.containsKey('max_tokens'), isFalse);
    });

    test('serialises snake_case parameters', () {
      final json = const ChatRequest(
        model: 'm',
        messages: [ChatMessage.system('be terse'), ChatMessage.user('hi')],
        maxTokens: 128,
        temperature: 0.2,
        frequencyPenalty: 0.5,
        repetitionPenalty: 1.1,
        stop: ['\n'],
        test: true,
      ).toJson();

      expect(json['max_tokens'], 128);
      expect(json['temperature'], 0.2);
      expect(json['frequency_penalty'], 0.5);
      expect(json['repetition_penalty'], 1.1);
      expect(json['stop'], ['\n']);
      expect(json['test'], true);
      expect(json['messages'], [
        {'role': 'system', 'content': 'be terse'},
        {'role': 'user', 'content': 'hi'},
      ]);
    });

    test('extra fields override typed ones', () {
      final json = const ChatRequest(
        model: 'm',
        messages: [],
        temperature: 0.1,
        extra: {'temperature': 0.9, 'top_k': 40},
      ).toJson();

      expect(json['temperature'], 0.9);
      expect(json['top_k'], 40);
    });
  });

  group('ChatCompletion', () {
    test('parses a standard completion', () {
      final completion = ChatCompletion.fromJson({
        'id': 'cmpl-1',
        'model': 'bitmeshai/chat-now-nano',
        'created': 1785153600,
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': '{"amount":"12.50"}'},
            'finish_reason': 'stop',
          }
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 5,
          'total_tokens': 15,
        },
      });

      expect(completion.id, 'cmpl-1');
      expect(completion.text, '{"amount":"12.50"}');
      expect(completion.choices.single.finishReason, 'stop');
      expect(completion.usage?.totalTokens, 15);
      expect(completion.created?.year, 2026);
      expect(completion.raw['model'], 'bitmeshai/chat-now-nano');
    });

    test('flattens multi-part content', () {
      final completion = ChatCompletion.fromJson({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': 'Hello '},
                {'type': 'text', 'text': 'world'},
              ],
            },
          }
        ],
      });

      expect(completion.text, 'Hello world');
    });

    test('text is null when the model returned nothing', () {
      expect(ChatCompletion.fromJson({'choices': <Object>[]}).text, isNull);
      expect(
        ChatCompletion.fromJson({
          'choices': [
            {'message': {'role': 'assistant', 'content': ''}}
          ]
        }).text,
        isNull,
      );
    });

    test('survives unexpected shapes without throwing', () {
      final completion = ChatCompletion.fromJson({'choices': 'nope'});
      expect(completion.choices, isEmpty);
      expect(completion.text, isNull);
    });
  });

  group('JobStatus', () {
    test('maps the API vocabularies', () {
      expect(JobStatus.parse('in_progress'), JobStatus.inProgress);
      expect(JobStatus.parse('IN-PROGRESS'), JobStatus.inProgress);
      expect(JobStatus.parse('processing'), JobStatus.inProgress);
      expect(JobStatus.parse('completed'), JobStatus.completed);
      expect(JobStatus.parse('succeeded'), JobStatus.completed);
      expect(JobStatus.parse('failed'), JobStatus.failed);
      expect(JobStatus.parse('canceled'), JobStatus.cancelled);
      expect(JobStatus.parse('pending'), JobStatus.queued);
      expect(JobStatus.parse(null), JobStatus.unknown);
      expect(JobStatus.parse('brand_new_state'), JobStatus.unknown);
    });

    test('unknown statuses are not terminal, so polling continues', () {
      expect(JobStatus.unknown.isTerminal, isFalse);
      expect(JobStatus.completed.isTerminal, isTrue);
      expect(JobStatus.failed.isTerminal, isTrue);
      expect(JobStatus.completed.isSuccess, isTrue);
      expect(JobStatus.failed.isSuccess, isFalse);
    });
  });

  group('VideoJob', () {
    test('parses a completed job with nested outputs', () {
      final job = VideoJob.fromJson({
        'id': 'vid-1',
        'status': 'completed',
        'width': 1280,
        'height': 720,
        'created_at': '2026-07-27T10:00:00Z',
        'outputs': {'video_url': 'https://api.bitmesh.ai/imgrslt/xyz'},
        'cost': 0.42,
      });

      expect(job.id, 'vid-1');
      expect(job.isCompleted, isTrue);
      expect(job.videoUrl, 'https://api.bitmesh.ai/imgrslt/xyz');
      expect(job.width, 1280);
      expect(job.cost, 0.42);
      expect(job.createdAt?.month, 7);
    });

    test('parses an in-progress job', () {
      final job = VideoJob.fromJson({'id': 'v', 'status': 'in_progress'});
      expect(job.status, JobStatus.inProgress);
      expect(job.isTerminal, isFalse);
      expect(job.videoUrl, isNull);
      expect(job.rawStatus, 'in_progress');
    });

    test('extracts nested error messages', () {
      final job = VideoJob.fromJson({
        'id': 'v',
        'status': 'failed',
        'error': {'message': 'moderation blocked the prompt'},
      });
      expect(job.error, 'moderation blocked the prompt');
    });
  });

  group('VideoRequest', () {
    test('serialises keyframes', () {
      final json = const VideoRequest(
        prompt: 'a cat',
        model: 'm',
        seconds: '5',
        outputFormat: 'MP4',
        frameImages: [
          VideoFrameImage(inputImage: 'https://x/1.png', frame: 0),
        ],
      ).toJson();

      expect(json['seconds'], '5');
      expect(json['output_format'], 'MP4');
      expect(json['frame_images'], [
        {'input_image': 'https://x/1.png', 'frame': 0}
      ]);
      expect(json.containsKey('fps'), isFalse);
    });
  });

  group('TranscriptionJob', () {
    test('parses a finished transcript', () {
      final job = TranscriptionJob.fromJson({
        'id': 'tr-1',
        'status': 'completed',
        'text': 'coffee and a bagel',
        'language': 'en',
        'speech_models': ['whisper-large'],
      });

      expect(job.isCompleted, isTrue);
      expect(job.text, 'coffee and a bagel');
      expect(job.language, 'en');
      expect(job.speechModels, ['whisper-large']);
    });

    test('finds the transcript nested under result', () {
      final job = TranscriptionJob.fromJson({
        'id': 'tr-2',
        'status': 'completed',
        'result': {'text': 'nested transcript'},
      });
      expect(job.text, 'nested transcript');
    });
  });

  group('ImageResponse', () {
    test('resolves URLs and object ids', () {
      final response = ImageResponse.fromJson({
        'data': [
          {'url': 'https://cdn.example/1.png'},
          {'object_id': 'obj-2'},
          {'url': '/imgrslt/obj-3'},
        ],
      });

      expect(response.images, hasLength(3));
      expect(response.first?.resolveUrl('https://api.bitmesh.ai'),
          'https://cdn.example/1.png');
      expect(response.images[1].resolveUrl('https://api.bitmesh.ai'),
          'https://api.bitmesh.ai/imgrslt/obj-2');
      expect(response.images[2].resolveUrl('https://api.bitmesh.ai/'),
          'https://api.bitmesh.ai/imgrslt/obj-3');
    });
  });

  group('ToolTask', () {
    test('finds the task id and output URLs at any depth', () {
      final task = ToolTask.fromJson({
        'data': {'task_id': 'task-9', 'status': 'processing'},
        'result': {
          'images': [
            {'image_url': 'https://api.bitmesh.ai/imgrslt/out-1'}
          ]
        },
      });

      expect(task.taskId, 'task-9');
      expect(task.status, JobStatus.inProgress);
      expect(task.outputUrl, 'https://api.bitmesh.ai/imgrslt/out-1');
    });
  });

  group('BitmeshFile', () {
    test('infers the content type from the extension', () {
      expect(BitmeshFile.fromPath('/tmp/a.m4a').contentType, 'audio/mp4');
      expect(BitmeshFile.fromPath('/tmp/a.WAV').contentType, 'audio/wav');
      expect(BitmeshFile.fromBytes([1], filename: 'x.png').contentType,
          'image/png');
      expect(BitmeshFile.fromPath('/tmp/no-extension').contentType, isNull);
    });

    test('an explicit content type wins', () {
      expect(
        BitmeshFile.fromPath('/tmp/a.m4a', contentType: 'audio/x-custom')
            .contentType,
        'audio/x-custom',
      );
    });

    test('derives the filename from the path', () {
      expect(BitmeshFile.fromPath('/a/b/c/note.m4a').filename, 'note.m4a');
      expect(BitmeshFile.fromPath(r'C:\tmp\note.m4a').filename, 'note.m4a');
    });

    test('rejects an empty path', () {
      expect(() => BitmeshFile.fromPath('  '),
          throwsA(isA<BitmeshArgumentException>()));
    });

    test('withField keeps the payload but renames the form field', () {
      final file = BitmeshFile.fromBytes([1, 2], filename: 'x.png');
      final renamed = file.withField('image');
      expect(renamed.field, 'image');
      expect(renamed.bytes, [1, 2]);
      expect(renamed.filename, 'x.png');
    });
  });

  group('RetryPolicy', () {
    test('backs off exponentially and caps at maxDelay', () {
      const policy = RetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 500),
        backoffFactor: 2.0,
        useJitter: false,
      );

      expect(policy.delayFor(1), const Duration(milliseconds: 100));
      expect(policy.delayFor(2), const Duration(milliseconds: 200));
      expect(policy.delayFor(3), const Duration(milliseconds: 400));
      expect(policy.delayFor(4), const Duration(milliseconds: 500));
      expect(policy.delayFor(50), const Duration(milliseconds: 500));
    });

    test('jitter stays within the computed bound', () {
      const policy = RetryPolicy(initialDelay: Duration(milliseconds: 100));
      for (var i = 0; i < 100; i++) {
        final delay = policy.delayFor(1);
        expect(delay, lessThanOrEqualTo(const Duration(milliseconds: 100)));
        expect(delay, greaterThanOrEqualTo(Duration.zero));
      }
    });

    test('Retry-After wins but is capped', () {
      const policy = RetryPolicy(maxDelay: Duration(seconds: 10));
      expect(policy.delayFor(1, retryAfter: const Duration(seconds: 3)),
          const Duration(seconds: 3));
      expect(policy.delayFor(1, retryAfter: const Duration(minutes: 5)),
          const Duration(seconds: 10));
    });

    test('none() disables retries', () {
      expect(const RetryPolicy.none().isEnabled, isFalse);
      expect(const RetryPolicy().isEnabled, isTrue);
    });
  });
}
