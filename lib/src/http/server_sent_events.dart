import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import '../exceptions.dart';

/// One server-sent event: an optional `event:` name and its `data:` lines.
@immutable
class ServerSentEvent {
  const ServerSentEvent({required this.data, this.event, this.id});

  /// The `event:` field, when the server named the event (Anthropic does).
  final String? event;

  /// The `id:` field, when present.
  final String? id;

  /// The event's `data:` lines, joined with newlines.
  final String data;

  /// True for OpenAI's end-of-stream marker, `data: [DONE]`.
  bool get isDone => data.trim() == '[DONE]';

  /// [data] parsed as a JSON object.
  Map<String, dynamic> json() {
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException catch (e) {
      throw BitmeshSerializationException(
        'A streamed event is not valid JSON: ${e.message}',
        body: data,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw BitmeshSerializationException(
        'Expected a JSON object in a streamed event.',
        body: data,
      );
    }
    return decoded;
  }

  @override
  String toString() => 'ServerSentEvent(${event ?? 'message'}: $data)';
}

/// Turns a raw response body into [ServerSentEvent]s, following the
/// `text/event-stream` format: fields per line, events ended by a blank line,
/// comments (`:`) ignored.
class ServerSentEventDecoder
    extends StreamTransformerBase<List<int>, ServerSentEvent> {
  const ServerSentEventDecoder();

  @override
  Stream<ServerSentEvent> bind(Stream<List<int>> stream) async* {
    String? event;
    String? id;
    final data = <String>[];

    ServerSentEvent? flush() {
      final result = data.isEmpty
          ? null
          : ServerSentEvent(data: data.join('\n'), event: event, id: id);
      event = null;
      data.clear();
      return result;
    }

    final lines =
        stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isEmpty) {
        final complete = flush();
        if (complete != null) yield complete;
        continue;
      }
      if (line.startsWith(':')) continue;

      final colon = line.indexOf(':');
      final field = colon == -1 ? line : line.substring(0, colon);
      var value = colon == -1 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'data':
          data.add(value);
        case 'event':
          event = value;
        case 'id':
          id = value;
      }
    }

    // A stream that ends without a final blank line still delivers its event.
    final last = flush();
    if (last != null) yield last;
  }
}
