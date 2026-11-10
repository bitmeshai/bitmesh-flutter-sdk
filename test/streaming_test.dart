import 'dart:async';
import 'dart:convert';

import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';
import 'package:bitmesh_flutter_sdk/src/http/server_sent_events.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Answers every request with [respond], recording what was sent.
class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.respond);

  final FutureOr<http.StreamedResponse> Function(http.Request request) respond;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) copy.body = request.body;
    requests.add(copy);
    return respond(copy);
  }
}

http.StreamedResponse _events(
  List<String> pieces, {
  Map<String, String> headers = const {},
}) =>
    http.StreamedResponse(
      Stream.fromIterable(pieces.map(utf8.encode)),
      200,
      headers: {'content-type': 'text/event-stream', ...headers},
    );

void main() {
  const key = 'bmk_test0123456789';
  const fastRetries = RetryPolicy(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 1),
    maxDelay: Duration(milliseconds: 2),
    useJitter: false,
  );

  BitmeshClient clientWith(
    _StreamingClient http, {
    RetryPolicy retryPolicy = const RetryPolicy.none(),
  }) =>
      BitmeshClient(
        apiKey: key,
        options: BitmeshOptions(retryPolicy: retryPolicy),
        httpClient: http,
      );

  const request = ChatRequest(
    model: 'bitmeshai/chat-now-nano',
    messages: [ChatMessage.user('Hello')],
  );

  group('server-sent events', () {
    Future<List<ServerSentEvent>> decode(List<String> pieces) =>
        Stream<List<int>>.fromIterable(pieces.map(utf8.encode))
        .transform(const ServerSentEventDecoder())
        .toList();

    test('events split across network reads are joined', () async {
      final events = await decode([
        'data: {"a":',
        '1}\n\nda',
        'ta: [DONE]\n\n',
      ]);
      expect(events.map((e) => e.data), ['{"a":1}', '[DONE]']);
      expect(events.last.isDone, isTrue);
    });

    test('event names, comments, CRLF and multi-line data', () async {
      final events = await decode([
        ': keep-alive\r\n',
        'event: message_start\r\ndata: {"x":1}\r\n\r\n',
        'data: line one\ndata: line two\n\n',
      ]);
      expect(events[0].event, 'message_start');
      expect(events[0].json(), {'x': 1});
      expect(events[1].event, isNull);
      expect(events[1].data, 'line one\nline two');
    });

    test('a last event without a blank line is still delivered', () async {
      final events = await decode(['data: tail']);
      expect(events.single.data, 'tail');
    });
  });

  group('chat.stream', () {
    test('sends stream: true and yields text, then usage', () async {
      final http = _StreamingClient((_) => _events([
            'data: {"choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}\n\n',
            'data: {"choices":[{"index":0,"delta":{"content":"There"}}]}\n\n',
            'data: {"choices":[{"index":0,"delta":{"content":" are plenty."},"finish_reason":"stop"}]}\n\n',
            'data: {"choices":[],"usage":{"prompt_tokens":51,"completion_tokens":4,"total_tokens":55}}\n\n',
            'data: [DONE]\n\n',
          ]));
      final client = clientWith(http);

      final chunks = await client.chat.stream(request).toList();

      final sent = http.requests.single;
      expect(sent.url.path, '/v2/chat');
      expect(sent.headers['Accept'], 'text/event-stream');
      expect(sent.headers['Authorization'], 'Bearer $key');
      expect((jsonDecode(sent.body) as Map)['stream'], isTrue);

      expect(chunks.map((c) => c.text).join(), 'There are plenty.');
      expect(chunks[2].finishReason, 'stop');
      expect(chunks.last.usage?.totalTokens, 55);
    });

    test('streamText collects the reply and reports each piece', () async {
      final client = clientWith(_StreamingClient((_) => _events([
            'data: {"choices":[{"index":0,"delta":{"content":"Hi"}}]}\n\n',
            'data: {"choices":[{"index":0,"delta":{"content":" there"}}]}\n\n',
            'data: [DONE]\n\n',
          ])));

      final pieces = <String>[];
      final reply =
          await client.chat.streamText(request, onText: pieces.add);

      expect(reply, 'Hi there');
      expect(pieces, ['Hi', ' there']);
    });

    test('an error before the stream starts is a typed exception', () async {
      final client = clientWith(_StreamingClient((_) => http.StreamedResponse(
            Stream.value(utf8.encode('{"error":"Insufficient balance"}')),
            402,
            headers: {'content-type': 'application/json'},
          )));

      await expectLater(
        client.chat.stream(request).toList(),
        throwsA(isA<BitmeshInsufficientBalanceException>()
            .having((e) => e.message, 'message', 'Insufficient balance')),
      );
    });

    test('a 429 before the stream starts is retried', () async {
      var attempts = 0;
      final client = clientWith(
        _StreamingClient((_) {
          attempts++;
          return attempts == 1
              ? http.StreamedResponse(
                  Stream.value(utf8.encode('{"error":"Too many"}')), 429)
              : _events(['data: {"choices":[{"delta":{"content":"ok"}}]}\n\n']);
        }),
        retryPolicy: fastRetries,
      );

      final chunks = await client.chat.stream(request).toList();
      expect(attempts, 2);
      expect(chunks.single.text, 'ok');
    });

    test('an error event mid-stream throws', () async {
      final client = clientWith(_StreamingClient((_) => _events([
            'data: {"choices":[{"delta":{"content":"Hal"}}]}\n\n',
            'data: {"error":{"message":"upstream overloaded"}}\n\n',
          ])));

      final texts = <String>[];
      await expectLater(
        client.chat.stream(request).map((c) => texts.add(c.text)).drain<void>(),
        throwsA(isA<BitmeshApiException>()
            .having((e) => e.message, 'message', 'upstream overloaded')),
      );
      expect(texts, ['Hal']);
    });

    test('cancelling stops reading the response', () async {
      final body = StreamController<List<int>>();
      final client = clientWith(_StreamingClient((_) => http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          )));

      body.add(utf8.encode('data: {"choices":[{"delta":{"content":"a"}}]}\n\n'));
      final first = await client.chat.stream(request).first;

      expect(first.text, 'a');
      // `first` cancels the subscription, which cancels the body stream.
      await Future<void>.delayed(Duration.zero);
      expect(body.hasListener, isFalse);
    });
  });

  group('proxy', () {
    test('post forwards to /v2/proxy/{provider}/{path} with the key', () async {
      final http = _StreamingClient((_) => _events(
            ['{"choices":[{"message":{"content":"Hi"}}]}'],
            headers: {'content-type': 'application/json'},
          ));
      final client = clientWith(http);

      final reply = await client.proxy.post(
        'anthropic',
        '/v1/messages',
        {'model': 'claude', 'max_tokens': 10},
        headers: {'anthropic-version': '2023-06-01'},
      );

      final sent = http.requests.single;
      expect(sent.method, 'POST');
      expect(sent.url.path, '/v2/proxy/anthropic/v1/messages');
      expect(sent.headers['Authorization'], 'Bearer $key');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      expect(jsonDecode(sent.body), {'model': 'claude', 'max_tokens': 10});
      expect(reply['choices'], isNotEmpty);
    });

    test('a provider header cannot replace the key', () async {
      final http = _StreamingClient((_) => _events(['{}'],
          headers: {'content-type': 'application/json'}));
      final client = clientWith(http);

      await client.proxy.get('openai', 'v1/models',
          headers: {'Authorization': 'Bearer sk-provider'});

      expect(http.requests.single.headers['Authorization'], 'Bearer $key');
    });

    test('send exposes the request id and status', () async {
      final client = clientWith(_StreamingClient((_) => _events(
            ['{"data":[]}'],
            headers: {'x-bitmesh-request-id': '42'},
          )));

      final response = await client.proxy.send('openai', 'v1/models');
      expect(response.statusCode, 200);
      expect(response.requestId, '42');
    });

    test('stream yields provider events with their names', () async {
      final http = _StreamingClient((_) => _events([
            'event: content_block_delta\ndata: {"delta":{"text":"Hi"}}\n\n',
            'event: message_stop\ndata: {"type":"message_stop"}\n\n',
          ]));
      final client = clientWith(http);

      final events = await client.proxy
          .stream('anthropic', 'v1/messages', {'model': 'claude'}).toList();

      expect((jsonDecode(http.requests.single.body) as Map)['stream'], isTrue);
      expect(events.map((e) => e.event), ['content_block_delta', 'message_stop']);
    });

    test('a refused proxy request throws with the error', () async {
      final client = clientWith(_StreamingClient((_) => http.StreamedResponse(
            Stream.value(utf8.encode(
                '{"error":"No active proxy plan. Choose a plan in the dashboard to use proxy keys."}')),
            402,
          )));

      await expectLater(
        client.proxy.post('openai', 'v1/chat/completions', {}),
        throwsA(isA<BitmeshInsufficientBalanceException>()),
      );
    });

    test('an invalid provider name is refused before sending', () {
      final client = clientWith(_StreamingClient((_) => _events([])));
      expect(
        () => client.proxy.post('Open AI', 'v1/chat/completions', {}),
        throwsA(isA<BitmeshArgumentException>()),
      );
    });
  });
}
