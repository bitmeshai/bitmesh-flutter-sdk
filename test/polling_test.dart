import 'dart:convert';

import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final credentials = BitmeshCredentials(key: 'key', secret: 'secret');

  const fastPolling = PollingOptions(
    interval: Duration(milliseconds: 1),
    timeout: Duration(seconds: 5),
  );

  BitmeshClient clientWith(MockClientHandler handler) => BitmeshClient(
        credentials: credentials,
        options: const BitmeshOptions(retryPolicy: RetryPolicy.none()),
        httpClient: MockClient(handler),
      );

  http.Response json(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  group('video jobs', () {
    test('generate() submits then polls until completion', () async {
      var polls = 0;
      final client = clientWith((request) async {
        if (request.method == 'POST') {
          return json({'id': 'vid-1', 'status': 'in_progress'});
        }
        polls++;
        return json({
          'id': 'vid-1',
          'status': polls < 3 ? 'in_progress' : 'completed',
          if (polls >= 3)
            'outputs': {'video_url': 'https://api.bitmesh.ai/imgrslt/out'},
        });
      });

      final updates = <String?>[];
      final job = await client.video.generate(
        const VideoRequest(prompt: 'a cat', model: 'm'),
        polling: fastPolling,
        onUpdate: (j) => updates.add(j.rawStatus),
      );

      expect(job.isCompleted, isTrue);
      expect(job.videoUrl, 'https://api.bitmesh.ai/imgrslt/out');
      expect(polls, 3);
      expect(updates, ['in_progress', 'in_progress', 'in_progress', 'completed']);
    });

    test('generate() skips polling when the job is already done', () async {
      var gets = 0;
      final client = clientWith((request) async {
        if (request.method == 'GET') gets++;
        return json({
          'id': 'vid-1',
          'status': 'completed',
          'outputs': {'video_url': 'u'},
        });
      });

      final job = await client.video.generate(
        const VideoRequest(prompt: 'p', model: 'm'),
        polling: fastPolling,
      );

      expect(job.videoUrl, 'u');
      expect(gets, 0);
    });

    test('a failed job throws with the API message', () async {
      final client = clientWith((request) async {
        if (request.method == 'POST') {
          return json({'id': 'vid-1', 'status': 'queued'});
        }
        return json({
          'id': 'vid-1',
          'status': 'failed',
          'error': {'message': 'prompt rejected'},
        });
      });

      try {
        await client.video.generate(
          const VideoRequest(prompt: 'p', model: 'm'),
          polling: fastPolling,
        );
        fail('should have thrown');
      } on BitmeshJobFailedException catch (e) {
        expect(e.jobId, 'vid-1');
        expect(e.status, 'failed');
        expect(e.message, 'prompt rejected');
      }
    });

    test('a failed job can be returned instead of thrown', () async {
      final client = clientWith((request) async => json({
            'id': 'vid-1',
            'status': 'failed',
            'error': {'message': 'nope'},
          }));

      final job = await client.video.waitFor(
        'vid-1',
        options: fastPolling.copyWith(throwOnFailure: false),
      );

      expect(job.status, JobStatus.failed);
      expect(job.error, 'nope');
    });

    test('polling gives up after the timeout', () async {
      final client = clientWith(
        (_) async => json({'id': 'vid-1', 'status': 'in_progress'}),
      );

      try {
        await client.video.waitFor(
          'vid-1',
          options: const PollingOptions(
            interval: Duration(milliseconds: 5),
            timeout: Duration(milliseconds: 40),
          ),
        );
        fail('should have thrown');
      } on BitmeshJobTimeoutException catch (e) {
        expect(e.jobId, 'vid-1');
        expect(e.lastStatus, 'inProgress');
      }
    });

    test('backoff widens the polling interval', () async {
      var polls = 0;
      final client = clientWith((_) async {
        polls++;
        return json({
          'id': 'vid-1',
          'status': polls < 4 ? 'in_progress' : 'completed',
        });
      });

      final stopwatch = Stopwatch()..start();
      await client.video.waitFor(
        'vid-1',
        options: const PollingOptions(
          interval: Duration(milliseconds: 10),
          backoffFactor: 2.0,
          maxInterval: Duration(milliseconds: 40),
          timeout: Duration(seconds: 5),
        ),
      );
      stopwatch.stop();

      // 10 + 20 + 40 = 70ms of waiting, minus scheduler slack.
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(60));
      expect(polls, 4);
    });

    test('unknown statuses keep the poll loop alive', () async {
      var polls = 0;
      final client = clientWith((_) async {
        polls++;
        return json({
          'id': 'vid-1',
          'status': polls < 2 ? 'something_new' : 'completed',
        });
      });

      final job = await client.video.waitFor('vid-1', options: fastPolling);
      expect(job.isCompleted, isTrue);
      expect(polls, 2);
    });

    test('an empty job id is rejected', () {
      final client = clientWith((_) async => json({}));
      expect(() => client.video.get('  '),
          throwsA(isA<BitmeshArgumentException>()));
      expect(() => client.video.waitFor(''),
          throwsA(isA<BitmeshArgumentException>()));
    });
  });

  group('transcription jobs', () {
    test('transcribe() uploads then polls for the transcript', () async {
      var polls = 0;
      final client = clientWith((request) async {
        if (request.method == 'POST') {
          return json({'id': 'tr-1', 'status': 'queued'});
        }
        polls++;
        return json({
          'id': 'tr-1',
          'status': polls < 2 ? 'processing' : 'completed',
          if (polls >= 2) 'text': 'one large coffee',
        });
      });

      final job = await client.transcription.transcribe(
        BitmeshFile.fromBytes([1, 2, 3], filename: 'note.m4a'),
        speechModels: ['whisper-large'],
        polling: fastPolling,
      );

      expect(job.text, 'one large coffee');
      expect(polls, 2);
    });
  });

  group('tool tasks', () {
    test('run() submits then polls query-async-task-result', () async {
      final bodies = <String>[];
      var polls = 0;
      final client = clientWith((request) async {
        bodies.add(request.url.path);
        if (request.url.path.endsWith('background-removal')) {
          return json({'task_id': 'task-1', 'status': 'processing'});
        }
        polls++;
        return json({
          'task_id': 'task-1',
          'status': polls < 2 ? 'processing' : 'success',
          'result': {'image_url': '/imgrslt/cutout'},
        });
      });

      final task = await client.tools.backgroundRemoval(
        BitmeshFile.fromBytes([1], filename: 'in.png'),
      );
      expect(task.taskId, 'task-1');

      final done = await client.tools.waitFor('task-1', options: fastPolling);
      expect(done.isCompleted, isTrue);
      expect(done.outputUrl, '/imgrslt/cutout');
      expect(bodies.last, '/tools/query-async-task-result');
    });

    test('results are fetched unsigned as text or bytes', () async {
      final client = clientWith((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response('cutout-bytes', 200);
      });

      expect(await client.tools.fetchResult('/imgrslt/cutout'), 'cutout-bytes');
      expect(
        await client.tools.fetchResultBytes(
          'https://api.bitmesh.ai/imgrslt/cutout',
        ),
        isNotEmpty,
      );
    });
  });

  group('compat layer', () {
    test('raw methods mirror the original client API', () async {
      final paths = <String>[];
      final client = clientWith((request) async {
        paths.add('${request.method} ${request.url.path}');
        return json({'ok': true});
      });

      await client.chat({'model': 'm'});
      await client.image({'prompt': 'p'});
      await client.video({'prompt': 'p'});
      await client.getVideo('v1');
      await client.getTranscribeRecorded('t1');
      await client.toolsQueryAsyncTaskResult('task-1');
      await client.getToolsResult('/imgrslt/x');

      expect(paths, [
        'POST /chat',
        'POST /image',
        'POST /video',
        'GET /video/v1',
        'GET /transcribe-recorded/t1',
        'POST /tools/query-async-task-result',
        'GET /imgrslt/x',
      ]);
    });
  });
}
