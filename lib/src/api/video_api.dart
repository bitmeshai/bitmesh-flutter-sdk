import '../exceptions.dart';
import '../http/bitmesh_transport.dart';
import '../models/video.dart';
import '../polling.dart';

/// `POST /video` and `GET /video/{id}` — video generation jobs.
class VideoApi {
  VideoApi(this._transport);

  final BitmeshTransport _transport;

  /// Submits a generation job and returns immediately.
  Future<VideoJob> create(VideoRequest request) async {
    final json = await _transport.postJson('/video', request.toJson());
    return VideoJob.fromJson(json);
  }

  /// Fetches the current state of a job.
  Future<VideoJob> get(String id, {Map<String, String> query = const {}}) async {
    final json = await _transport.getJson(
      'video/${Uri.encodeComponent(_requireId(id))}',
      query: query,
    );
    return VideoJob.fromJson(json);
  }

  /// Polls [get] until the job finishes.
  ///
  /// Throws [BitmeshJobFailedException] if it fails and
  /// [BitmeshJobTimeoutException] if it outlives [PollingOptions.timeout].
  Future<VideoJob> waitFor(
    String id, {
    PollingOptions options = const PollingOptions(),
    void Function(VideoJob job)? onUpdate,
  }) {
    final jobId = _requireId(id);
    return pollJob<VideoJob>(
      jobId: jobId,
      fetch: () => get(jobId),
      statusOf: (job) => job.status,
      errorOf: (job) => job.error,
      options: options,
      onUpdate: onUpdate,
    );
  }

  /// Submits a job and waits for the finished video in one call.
  Future<VideoJob> generate(
    VideoRequest request, {
    PollingOptions polling = const PollingOptions(),
    void Function(VideoJob job)? onUpdate,
  }) async {
    final job = await create(request);
    onUpdate?.call(job);
    if (job.isCompleted) return job;
    if (job.id.isEmpty) {
      throw const BitmeshSerializationException(
        'The API did not return a job id for the video request.',
      );
    }
    return waitFor(job.id, options: polling, onUpdate: onUpdate);
  }

  /// Raw request/response.
  Future<Map<String, dynamic>> createRaw(Map<String, dynamic> payload) =>
      _transport.postJson('/video', payload);

  /// Raw job lookup.
  Future<Map<String, dynamic>> getRaw(
    String id, {
    Map<String, String> query = const {},
  }) =>
      _transport.getJson(
        'video/${Uri.encodeComponent(_requireId(id))}',
        query: query,
      );

  /// Alias for [createRaw], so `client.video({...})` works.
  Future<Map<String, dynamic>> call(Map<String, dynamic> payload) =>
      createRaw(payload);

  String _requireId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw const BitmeshArgumentException('Video job id is required.');
    }
    return trimmed;
  }
}
