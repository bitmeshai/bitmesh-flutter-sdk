import '../bitmesh_file.dart';
import '../exceptions.dart';
import '../http/bitmesh_transport.dart';
import '../models/transcription.dart';
import '../polling.dart';
import '../realtime/realtime_connect.dart';
import '../realtime/realtime_session.dart';

/// Speech to text: `POST /v2/transcribe-recorded` and
/// `GET /v2/transcribe-recorded/{id}` for recorded audio, and
/// [connectRealtime] (`/v2/transcribe-realtime`) for audio as it is spoken.
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

  /// Opens a real-time transcription session: a WebSocket to
  /// `/v2/transcribe-realtime`. Send audio as it is recorded and the transcript
  /// comes back turn by turn; see [RealtimeTranscriptionSession].
  ///
  /// [sampleRate] is that of the audio you will send, in Hz. [speechModel] is
  /// one of [RealtimeSpeechModel] (default `universal-3-6-pro`). [encoding] is
  /// `pcm_s16le` (default) or `pcm_mulaw`. [formatTurns] punctuates and cases
  /// final turns of the `universal-streaming-*` models. [languageDetection]
  /// adds the language to each turn. [query] passes further connection
  /// settings of the transcription service.
  ///
  /// A refused connection throws before any audio is sent: a
  /// [BitmeshAuthenticationException] (`401`, `403`),
  /// [BitmeshInsufficientBalanceException] (`402`: less than a minute's
  /// balance), [BitmeshBadRequestException] (`422`),
  /// [BitmeshRateLimitException] (`429`: too many sessions open on the key)
  /// or [BitmeshServerException]. Needs `dart:io`: on the web it throws
  /// [BitmeshConfigurationException].
  Future<RealtimeTranscriptionSession> connectRealtime({
    int sampleRate = 16000,
    String? speechModel,
    String? encoding,
    bool? formatTurns,
    bool? languageDetection,
    Map<String, String> query = const {},
  }) async {
    if (sampleRate <= 0) {
      throw const BitmeshArgumentException('sampleRate must be positive.');
    }
    final uri = _transport.apiUri('transcribe-realtime', query: {
      'sample_rate': '$sampleRate',
      if (speechModel != null) 'speech_model': speechModel,
      if (encoding != null) 'encoding': encoding,
      if (formatTurns != null) 'format_turns': '$formatTurns',
      if (languageDetection != null) 'language_detection': '$languageDetection',
      ...query,
    });
    final socket = await connectRealtimeSocket(
      uri,
      await _transport.authenticatedHeaders(),
      _transport.options.timeout,
    );
    return RealtimeTranscriptionSession(socket);
  }

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
