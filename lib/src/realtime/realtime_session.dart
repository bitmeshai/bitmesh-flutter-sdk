import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../exceptions.dart';
import '../models/realtime.dart';

/// The WebSocket a [RealtimeTranscriptionSession] runs on.
@internal
abstract interface class RealtimeSocket {
  /// Messages from the server: `String` for text, `List<int>` for binary.
  Stream<dynamic> get messages;

  void add(Object data);

  Future<void> close([int? code, String? reason]);

  int? get closeCode;

  String? get closeReason;
}

/// An open real-time transcription session, from
/// `TranscriptionApi.connectRealtime`.
///
/// Send audio with [sendAudio] as it is recorded, read the transcript from
/// [events], and call [terminate] when you are done:
///
/// ```dart
/// final session = await client.transcription.connectRealtime(sampleRate: 16000);
/// session.events.listen((event) {
///   if (event is RealtimeTurn && event.endOfTurn) print(event.transcript);
/// });
/// await for (final chunk in microphone) {
///   session.sendAudio(chunk); // 16-bit mono PCM, about 50 ms at a time
/// }
/// final end = await session.terminate();
/// print('${end?.sessionDurationSeconds} s billed');
/// ```
///
/// The session is billed for the time it is open, silence included, so end
/// it as soon as you are done.
class RealtimeTranscriptionSession {
  @internal
  RealtimeTranscriptionSession(this._socket) {
    _begun.future.ignore();
    _subscription = _socket.messages.listen(
      _onMessage,
      onError: (Object error) => _events.addError(BitmeshNetworkException(
        'The real-time transcription connection failed.',
        cause: error,
      )),
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  final RealtimeSocket _socket;
  late final StreamSubscription<dynamic> _subscription;
  final _events = StreamController<RealtimeEvent>();
  final _begun = Completer<RealtimeBegin>();
  final _done = Completer<RealtimeTermination?>();
  RealtimeTermination? _termination;
  bool _closing = false;
  bool _closed = false;

  /// Every message of the session, in order, from `Begin` to `Termination`.
  ///
  /// Messages are kept until you listen, so none are missed. The stream ends
  /// when the session closes; a close other than a normal one adds a
  /// [BitmeshRealtimeClosedException] first. It can be listened to once.
  Stream<RealtimeEvent> get events => _events.stream;

  /// Completes with the session's `Begin` message.
  Future<RealtimeBegin> get begun => _begun.future;

  /// Completes when the connection has closed, with the `Termination`
  /// message, or `null` when the session closed without one.
  Future<RealtimeTermination?> get done => _done.future;

  /// `true` once the connection has closed.
  bool get isClosed => _closed;

  /// The close code, once closed: `1000` for a normal end.
  int? get closeCode => _closed ? (_socket.closeCode ?? 1006) : null;

  /// The close reason, once closed.
  String? get closeReason => _closed ? _socket.closeReason : null;

  /// Sends a piece of audio: raw 16-bit little-endian mono PCM at the session's
  /// sample rate (or μ-law with `encoding: 'pcm_mulaw'`). Send it as it is
  /// recorded, about 50 ms at a time: 1,600 bytes at 16 kHz.
  void sendAudio(List<int> audio) {
    _checkOpen();
    _socket.add(audio is Uint8List ? audio : Uint8List.fromList(audio));
  }

  /// Sends every piece of [audio] as it arrives, until the stream ends.
  Future<void> sendAudioStream(Stream<List<int>> audio) async {
    await for (final chunk in audio) {
      if (_closed || _closing) break;
      sendAudio(chunk);
    }
  }

  /// Ends the current turn now, without waiting for a pause.
  void forceEndpoint() => sendMessage({'type': 'ForceEndpoint'});

  /// Sends a JSON control message, such as `{"type": "UpdateConfiguration", ...}`.
  void sendMessage(Map<String, dynamic> message) {
    _checkOpen();
    _socket.add(jsonEncode(message));
  }

  /// Ends the session: turns still in progress arrive, then `Termination`,
  /// then the connection closes. Returns the `Termination` message.
  ///
  /// Closes the connection itself if the server hasn't within [timeout].
  Future<RealtimeTermination?> terminate({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_closed && !_closing) {
      _closing = true;
      _socket.add(jsonEncode({'type': 'Terminate'}));
    }
    return done.timeout(timeout, onTimeout: () async {
      await close();
      return done;
    });
  }

  /// Closes the connection straight away. Prefer [terminate], which lets the
  /// last turn arrive. The session is billed up to the close either way.
  Future<void> close() async {
    _closing = true;
    if (!_closed) await _socket.close(1000);
    await done;
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    Object? json;
    try {
      json = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (json is! Map) return;

    final event = RealtimeEvent.fromJson(Map<String, dynamic>.from(json));
    if (event is RealtimeBegin && !_begun.isCompleted) _begun.complete(event);
    if (event is RealtimeTermination) _termination = event;
    _events.add(event);
  }

  void _onDone() {
    _closed = true;
    final code = closeCode!;
    if (code != 1000) {
      final reason = closeReason;
      final error = BitmeshRealtimeClosedException(
        code,
        reason == null || reason.isEmpty
            ? (code == 1006
                ? 'The connection was lost.'
                : 'The session closed with code $code.')
            : reason,
      );
      _events.addError(error);
      if (!_begun.isCompleted) _begun.completeError(error);
    } else if (!_begun.isCompleted) {
      _begun.completeError(const BitmeshRealtimeClosedException(
        1000,
        'The session closed before it began.',
      ));
    }
    _done.complete(_termination);
    _events.close();
    _subscription.cancel();
  }

  void _checkOpen() {
    if (_closed || _closing) {
      throw StateError('The real-time transcription session has ended.');
    }
  }
}
