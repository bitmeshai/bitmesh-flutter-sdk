import 'package:meta/meta.dart';

import 'json_utils.dart';

/// The real-time transcription models, for the `speechModel` of
/// `TranscriptionApi.connectRealtime`.
abstract final class RealtimeSpeechModel {
  /// The default: 32 languages, switching mid-sentence, punctuated and cased.
  static const String universal36Pro = 'universal-3-6-pro';

  /// English only. Lowercase without punctuation unless `formatTurns` is set.
  static const String universalStreamingEnglish = 'universal-streaming-english';

  /// English, Spanish, German, French, Portuguese and Italian, one per turn.
  static const String universalStreamingMultilingual =
      'universal-streaming-multilingual';
}

/// A message from a real-time transcription session.
///
/// Sessions send one [RealtimeBegin], then a [RealtimeTurn] each time the
/// transcript changes, and a [RealtimeTermination] last. Message types this
/// SDK doesn't know come as [RealtimeOtherEvent].
@immutable
sealed class RealtimeEvent {
  const RealtimeEvent(this.raw);

  /// The message as received.
  final Map<String, dynamic> raw;

  /// The message's `type`.
  String get type => asString(raw['type']) ?? '';

  /// Parses one message from the server.
  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    switch (asString(json['type'])) {
      case 'Begin':
        return RealtimeBegin.fromJson(json);
      case 'Turn':
        return RealtimeTurn.fromJson(json);
      case 'Termination':
        return RealtimeTermination.fromJson(json);
      default:
        return RealtimeOtherEvent(json);
    }
  }
}

/// The session started.
final class RealtimeBegin extends RealtimeEvent {
  const RealtimeBegin(
      {required this.id, this.expiresAt, required Map<String, dynamic> raw})
      : super(raw);

  factory RealtimeBegin.fromJson(Map<String, dynamic> json) {
    final expires = asInt(json['expires_at']);
    return RealtimeBegin(
      id: asString(json['id']) ?? '',
      expiresAt: expires == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true),
      raw: json,
    );
  }

  /// The session id.
  final String id;

  /// The latest time the session may run to: an hour, or less when the
  /// balance covers less.
  final DateTime? expiresAt;

  @override
  String toString() => 'RealtimeBegin($id, expires: $expiresAt)';
}

/// The transcript of one turn so far.
///
/// The same turn is sent again each time it changes. It is final when
/// [endOfTurn] is `true`: keep the last one of each [turnOrder].
final class RealtimeTurn extends RealtimeEvent {
  const RealtimeTurn({
    required this.turnOrder,
    required this.transcript,
    required this.endOfTurn,
    this.isFormatted = false,
    this.languageCode,
    this.languageConfidence,
    required Map<String, dynamic> raw,
  }) : super(raw);

  factory RealtimeTurn.fromJson(Map<String, dynamic> json) => RealtimeTurn(
        turnOrder: asInt(json['turn_order']) ?? 0,
        transcript: asString(json['transcript']) ?? '',
        endOfTurn: json['end_of_turn'] == true,
        isFormatted: json['turn_is_formatted'] == true,
        languageCode: asString(json['language_code']),
        languageConfidence: asDouble(json['language_confidence']),
        raw: json,
      );

  /// Counts the turns of the session from 0.
  final int turnOrder;

  /// The words of the turn so far.
  final String transcript;

  /// `true` when the turn is finished and [transcript] won't change again.
  final bool endOfTurn;

  /// `true` when [transcript] is punctuated and cased.
  final bool isFormatted;

  /// The turn's language, with `languageDetection: true`.
  final String? languageCode;

  /// How sure the model is of [languageCode], from 0 to 1.
  final double? languageConfidence;

  /// Word-level detail (`text`, `start`, `end`, `confidence`), as received.
  List<Map<String, dynamic>> get words => [
        for (final word in (raw['words'] as List? ?? const []))
          if (word is Map) Map<String, dynamic>.from(word),
      ];

  @override
  String toString() =>
      'RealtimeTurn($turnOrder${endOfTurn ? ', final' : ''}: $transcript)';
}

/// The session ended. [sessionDurationSeconds] is the time billed.
final class RealtimeTermination extends RealtimeEvent {
  const RealtimeTermination({
    this.audioDurationSeconds,
    this.sessionDurationSeconds,
    required Map<String, dynamic> raw,
  }) : super(raw);

  factory RealtimeTermination.fromJson(Map<String, dynamic> json) =>
      RealtimeTermination(
        audioDurationSeconds: asDouble(json['audio_duration_seconds']),
        sessionDurationSeconds: asDouble(json['session_duration_seconds']),
        raw: json,
      );

  /// Seconds of audio the session received.
  final double? audioDurationSeconds;

  /// Seconds the session was open: the time it is billed for.
  final double? sessionDurationSeconds;

  @override
  String toString() => 'RealtimeTermination(audio: ${audioDurationSeconds}s, '
      'session: ${sessionDurationSeconds}s)';
}

/// A message type this SDK doesn't parse. [raw] has all of it.
final class RealtimeOtherEvent extends RealtimeEvent {
  const RealtimeOtherEvent(super.raw);

  @override
  String toString() => 'RealtimeOtherEvent($type)';
}
