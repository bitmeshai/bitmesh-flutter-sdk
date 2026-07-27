import '../bitmesh_file.dart';
import '../exceptions.dart';
import '../http/bitmesh_transport.dart';
import '../models/transcription.dart';
import '../polling.dart';

/// `POST /transcribe-recorded` and `GET /transcribe-recorded/{id}` — speech to
/// text for pre-recorded audio.
class TranscriptionApi {
  TranscriptionApi(this._transport);

  static const String _path = '/transcribe-recorded';

  final BitmeshTransport _transport;

  /// Uploads audio and returns the job immediately.
  ///
  /// [audio] can come from disk ([BitmeshFile.fromPath]) or memory
  /// ([BitmeshFile.fromBytes]); the form field is forced to `audio`.
  Future<TranscriptionJob> create(
    BitmeshFile audio, {
    List<String> speechModels = const [],
    Map<String, dynamic> fields = const {},
  }) async {
    final json = await _transport.postMultipart(
      _path,
      fields: {
        if (speechModels.isNotEmpty) 'speech_models': speechModels,
        ...fields,
      },
      files: [audio.withField('audio')],
    );
    return TranscriptionJob.fromJson(json);
  }

  /// Uploads audio from a file path.
  Future<TranscriptionJob> createFromPath(
    String path, {
    List<String> speechModels = const [],
    Map<String, dynamic> fields = const {},
  }) =>
      create(
        BitmeshFile.fromPath(path, field: 'audio'),
        speechModels: speechModels,
        fields: fields,
      );

  /// Fetches the current state of a transcription job.
  Future<TranscriptionJob> get(
    String id, {
    Map<String, String> query = const {},
  }) async {
    final json = await _transport.getJson(
      'transcribe-recorded/${Uri.encodeComponent(_requireId(id))}',
      query: query,
    );
    return TranscriptionJob.fromJson(json);
  }

  /// Polls [get] until the transcript is ready.
  Future<TranscriptionJob> waitFor(
    String id, {
    PollingOptions options = const PollingOptions(),
    void Function(TranscriptionJob job)? onUpdate,
  }) {
    final jobId = _requireId(id);
    return pollJob<TranscriptionJob>(
      jobId: jobId,
      fetch: () => get(jobId),
      statusOf: (job) => job.status,
      errorOf: (job) => job.error,
      options: options,
      onUpdate: onUpdate,
    );
  }

  /// Uploads audio and waits for the finished transcript in one call.
  Future<TranscriptionJob> transcribe(
    BitmeshFile audio, {
    List<String> speechModels = const [],
    Map<String, dynamic> fields = const {},
    PollingOptions polling = const PollingOptions(),
    void Function(TranscriptionJob job)? onUpdate,
  }) async {
    final job = await create(
      audio,
      speechModels: speechModels,
      fields: fields,
    );
    onUpdate?.call(job);
    if (job.isCompleted) return job;
    if (job.id.isEmpty) {
      throw const BitmeshSerializationException(
        'The API did not return a job id for the transcription request.',
      );
    }
    return waitFor(job.id, options: polling, onUpdate: onUpdate);
  }

  /// Raw multipart upload.
  Future<Map<String, dynamic>> createRaw(
    String audioFilePath, {
    Map<String, dynamic> fields = const {},
  }) =>
      _transport.postMultipart(
        _path,
        fields: fields,
        files: [BitmeshFile.fromPath(audioFilePath, field: 'audio')],
      );

  /// Raw job lookup.
  Future<Map<String, dynamic>> getRaw(
    String id, {
    Map<String, String> query = const {},
  }) =>
      _transport.getJson(
        'transcribe-recorded/${Uri.encodeComponent(_requireId(id))}',
        query: query,
      );

  String _requireId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw const BitmeshArgumentException('Transcription job id is required.');
    }
    return trimmed;
  }
}
