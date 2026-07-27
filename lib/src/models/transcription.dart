import 'package:meta/meta.dart';

import 'job_status.dart';
import 'json_utils.dart';

/// A transcription job, as returned by `POST /transcribe-recorded` and
/// `GET /transcribe-recorded/{id}`.
@immutable
class TranscriptionJob {
  const TranscriptionJob({
    required this.id,
    required this.status,
    required this.raw,
    this.rawStatus,
    this.text,
    this.language,
    this.speechModels = const [],
    this.durationSeconds,
    this.error,
  });

  final String id;
  final JobStatus status;

  /// Status string exactly as reported by the API.
  final String? rawStatus;

  /// The transcript, present once the job completes.
  final String? text;

  /// Detected or requested language code.
  final String? language;

  /// Models used for the transcription.
  final List<String> speechModels;

  /// Audio duration, when reported.
  final double? durationSeconds;

  /// Failure detail, when the job failed.
  final String? error;

  /// The unmodified response body.
  final Map<String, dynamic> raw;

  factory TranscriptionJob.fromJson(Map<String, dynamic> json) {
    final rawStatus = asString(pick(json, ['status', 'state']));
    final result = asMap(pick(json, ['result', 'results', 'outputs'])) ?? const {};
    final error = asMap(json['error']);

    return TranscriptionJob(
      id: asString(pick(json, ['id', 'job_id', 'task_id'])) ?? '',
      status: JobStatus.parse(rawStatus),
      rawStatus: rawStatus,
      text: asString(pick(json, ['text', 'transcript', 'transcription'])) ??
          asString(pick(result, ['text', 'transcript'])),
      language: asString(pick(json, ['language', 'language_code'])),
      speechModels:
          asStringList(pick(json, ['speech_models', 'models', 'model'])),
      durationSeconds: asDouble(pick(json, ['duration', 'audio_duration'])),
      error: error != null
          ? asString(error['message'])
          : asString(pick(json, ['error', 'error_message'])),
      raw: json,
    );
  }

  bool get isCompleted => status.isSuccess;
  bool get isTerminal => status.isTerminal;

  @override
  String toString() => 'TranscriptionJob($id, status: '
      '${rawStatus ?? status.name}, chars: ${text?.length ?? 0})';
}
