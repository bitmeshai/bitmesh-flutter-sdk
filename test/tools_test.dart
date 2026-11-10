import 'dart:convert';

import 'package:bitmesh/bitmesh.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Response bodies below are copied from the live API (November 2026).
void main() {
  const key = 'bmk_test0123456789';

  BitmeshClient clientWith(MockClientHandler handler) => BitmeshClient(
        apiKey: key,
        options: const BitmeshOptions(retryPolicy: RetryPolicy.none()),
        httpClient: MockClient(handler),
      );

  http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  const detail = {
    'status_code': 200,
    'code': '',
    'code_message': '',
    'message': '',
  };

  group('ToolTask from live responses', () {
    test('background removal: link in data.image_url', () {
      final task = ToolTask.fromJson({
        'data': {
          'image_url':
              'https://ailab-outputs.oss-accelerate.aliyuncs.com/x/2026-11-02-00/cut.png'
        },
        'error_code': 0,
        'request_id': '01A197DD-4E39-524B-9C34-E6D5EE61C1DC',
        'detail': detail,
        'status': 'success',
      });

      expect(task.isCompleted, isTrue);
      expect(task.outputUrl,
          'https://ailab-outputs.oss-accelerate.aliyuncs.com/x/2026-11-02-00/cut.png');
    });

    test('try-on submit: task id, no output yet', () {
      final task = ToolTask.fromJson({
        'error_code': 0,
        'request_id': '85200403',
        'task_id': '1793549228989.e65e0fb6-7ff6-dffd-5272-d1b8bf9510a2',
        'task_type': 'async',
        'detail': detail,
        'status': 'success',
      });

      expect(task.taskId, '1793549228989.e65e0fb6-7ff6-dffd-5272-d1b8bf9510a2');
      expect(task.outputUrls, isEmpty);
    });

    test('try-on poll: processing, then link in output.image_url', () {
      final running = ToolTask.fromJson({
        'error_code': 0,
        'task_status': 1,
        'detail': detail,
        'status': 'processing',
      });
      expect(running.status, JobStatus.inProgress);

      final done = ToolTask.fromJson({
        'error_code': 0,
        'output': {
          'image_url':
              'https://ailab-outputs.oss-accelerate.aliyuncs.com/aiScheduler/image2/edit/2026-11-02-00/out.png'
        },
        'task_status': 2,
        'detail': detail,
        'status': 'success',
      });
      expect(done.isCompleted, isTrue);
      expect(done.outputUrl,
          'https://ailab-outputs.oss-accelerate.aliyuncs.com/aiScheduler/image2/edit/2026-11-02-00/out.png');
    });

    test('a list of image links is collected', () {
      final task = ToolTask.fromJson({
        'data': {
          'images': ['https://example.com/a.png', 'https://example.com/b.png']
        },
        'status': 'success',
      });
      expect(task.outputUrls,
          ['https://example.com/a.png', 'https://example.com/b.png']);
    });

    test('image animate: video link, not the callback relay or inputs', () {
      final task = ToolTask.fromJson({
        'code': 0,
        'data': {
          'task_id': '06ae763e-0ce0-7475-8000-258b9a39351c',
          'id': '06ae763e-0ce0-7475-8000-258b9a39351c',
          'status': 'SUCCESS',
          'category': 'IMAGE_TO_VIDEO',
          'callback_url':
              'https://api.bitmesh.ai/tools/video/image-animate-callback/17935492801122',
          'seconds': 3,
          'output_videos': [
            {
              'url':
                  'https://assets-cdn.domoai.com/output/video/d0a0.mp4?q-signature=x',
              'width': 720,
              'height': 1280,
            }
          ],
          'credits': 6,
          'inputs': {
            'model': 'animate-2.4-faster',
            'image_url': 'https://assets-cdn.domoai.com/input/image/e05f.png',
          },
        },
      });

      expect(task.taskId, '06ae763e-0ce0-7475-8000-258b9a39351c');
      expect(task.isCompleted, isTrue);
      expect(task.outputUrls, [
        'https://assets-cdn.domoai.com/output/video/d0a0.mp4?q-signature=x'
      ]);
    });

    test('DomoAI and AiLabTools statuses', () {
      expect(JobStatus.parse('QUEUING'), JobStatus.queued);
      expect(JobStatus.parse('PENDING'), JobStatus.queued);
      expect(JobStatus.parse('PROCESSING'), JobStatus.inProgress);
      expect(JobStatus.parse('CANCELED'), JobStatus.cancelled);
      expect(JobStatus.parse('fail'), JobStatus.failed);
    });
  });

  group('multipart tool uploads', () {
    test('send booleans as 1 or 0 and numbers as text',
        () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({'task_id': 't', 'status': 'success'});
      });

      await client.tools.tryOnClothes(
        {
          'person_image': BitmeshFile.fromBytes([1], filename: 'p.png'),
          'top_garment': BitmeshFile.fromBytes([2], filename: 't.png'),
        },
        fields: {'restore_face': true, 'resolution': 1024, 'test': null},
      );

      final body = captured.body;
      expect(body, contains('name="restore_face"\r\n\r\n1\r\n'));
      expect(body, contains('name="resolution"\r\n\r\n1024\r\n'));
      expect(body, isNot(contains('name="test"')));
      expect(body, contains('name="person_image"; filename="p.png"'));
      expect(captured.url.path, '/v2/tools/portrait/try-on-clothes');
    });
  });

  group('image animate', () {
    test('sends the image base64-encoded in a JSON body', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({
          'code': 0,
          'data': {'task_id': '06ae763e-0ce0-7475-8000-258b9a39351c'},
        });
      });

      final task = await client.tools.imageAnimate(
        model: 'animate-2.4-faster',
        image: BitmeshFile.fromBytes([1, 2, 3], filename: 'cat.png'),
        seconds: 5,
        prompt: 'the cat blinks',
        aspectRatio: '9:16',
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, '/v2/tools/video/image-animate');
      expect(captured.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(captured.body), {
        'model': 'animate-2.4-faster',
        'image': {'bytes_base64_encoded': 'AQID'},
        'seconds': 5,
        'prompt': 'the cat blinks',
        'aspect_ratio': '9:16',
      });
      expect(task.taskId, '06ae763e-0ce0-7475-8000-258b9a39351c');
    });

    test('rejects a length outside 1 to 10 seconds before sending', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return jsonResponse({});
      });

      await expectLater(
        client.tools.imageAnimate(
          model: 'animate-2.4-faster',
          image: BitmeshFile.fromBytes([1], filename: 'cat.png'),
          seconds: 11,
        ),
        throwsA(isA<BitmeshArgumentException>()),
      );
      expect(called, isFalse);
    });

    test('waitForImageAnimate polls the status endpoint until SUCCESS',
        () async {
      final requests = <Uri>[];
      final statuses = ['QUEUING', 'PROCESSING', 'SUCCESS'];
      final client = clientWith((request) async {
        requests.add(request.url);
        final status = statuses[requests.length - 1];
        return jsonResponse({
          'code': 0,
          'data': {
            'task_id': 'task-1',
            'status': status,
            'output_videos': status == 'SUCCESS'
                ? [
                    {
                      'url': 'https://cdn.example/v.mp4',
                      'width': 720,
                      'height': 1280
                    }
                  ]
                : <Object>[],
          },
        });
      });

      final done = await client.tools.waitForImageAnimate(
        'task-1',
        test: true,
        options: const PollingOptions(interval: Duration(milliseconds: 1)),
      );

      expect(requests, hasLength(3));
      expect(requests.first.path, '/v2/tools/video/image-animate/task-1');
      expect(requests.first.queryParameters, {'test': '1'});
      expect(done.outputUrl, 'https://cdn.example/v.mp4');
    });

    test('a FAILED task throws', () async {
      final client = clientWith((request) async => jsonResponse({
            'code': 0,
            'data': {'task_id': 'task-1', 'status': 'FAILED'},
          }));

      await expectLater(
        client.tools.waitForImageAnimate('task-1',
            options: const PollingOptions(interval: Duration(milliseconds: 1))),
        throwsA(isA<BitmeshJobFailedException>()),
      );
    });
  });

  group('result downloads', () {
    test('an absolute link on another host is fetched as is', () async {
      final requests = <Uri>[];
      final client = clientWith((request) async {
        requests.add(request.url);
        return http.Response.bytes([7, 8], 200);
      });

      final bytes = await client.tools.fetchResultBytes(
          'https://ailab-outputs.oss-accelerate.aliyuncs.com/x/out.png');

      expect(bytes, [7, 8]);
      expect(requests.single.toString(),
          'https://ailab-outputs.oss-accelerate.aliyuncs.com/x/out.png');
    });
  });
}
