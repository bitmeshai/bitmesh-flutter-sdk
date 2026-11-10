import 'dart:convert';
import 'dart:typed_data';

import '../bitmesh_file.dart';
import '../exceptions.dart';
import '../http/bitmesh_transport.dart';
import '../models/tools.dart';
import '../polling.dart';

/// `/v2/tools/*`: ready-made image and video tools.
///
/// [backgroundRemoval] answers straight away with the result link in
/// [ToolTask.outputUrl]. [tryOnClothes] returns a task: poll
/// [queryAsyncTaskResult] (or let [waitFor] do it). [imageAnimate] returns a
/// task polled with [imageAnimateStatus] (or [waitForImageAnimate]). Download
/// a result with [fetchResultBytes].
class ToolsApi {
  ToolsApi(this._transport);

  final BitmeshTransport _transport;

  /// `POST /tools/general/background-removal`.
  Future<ToolTask> backgroundRemoval(
    BitmeshFile image, {
    Map<String, dynamic> fields = const {},
  }) =>
      submit(
        '/tools/general/background-removal',
        fields: fields,
        files: [image.withField('image')],
      );

  /// `POST /tools/portrait/try-on-clothes`.
  ///
  /// [files] maps form field names to uploads, e.g.
  /// `{'person_image': ..., 'clothes_image': ...}`.
  Future<ToolTask> tryOnClothes(
    Map<String, BitmeshFile> files, {
    Map<String, dynamic> fields = const {},
  }) =>
      submit(
        '/tools/portrait/try-on-clothes',
        fields: fields,
        files: files.entries.map((e) => e.value.withField(e.key)).toList(),
      );

  /// Submits any multipart `/tools` endpoint, including ones this SDK does not
  /// wrap yet.
  Future<ToolTask> submit(
    String path, {
    Map<String, dynamic> fields = const {},
    List<BitmeshFile> files = const [],
  }) async {
    final json = await _transport.postMultipart(
      path,
      fields: fields,
      files: files,
    );
    return ToolTask.fromJson(json);
  }

  /// `POST /tools/query-async-task-result`.
  Future<ToolTask> queryAsyncTaskResult(String taskId) async {
    final json = await _transport.postJson(
      '/tools/query-async-task-result',
      {'task_id': _requireId(taskId)},
    );
    return ToolTask.fromJson(json);
  }

  /// Polls [queryAsyncTaskResult] until the task reaches a terminal state.
  Future<ToolTask> waitFor(
    String taskId, {
    PollingOptions options = const PollingOptions(),
    void Function(ToolTask task)? onUpdate,
  }) {
    final id = _requireId(taskId);
    return pollJob<ToolTask>(
      jobId: id,
      fetch: () => queryAsyncTaskResult(id),
      statusOf: (task) => task.status,
      errorOf: (task) => task.error,
      options: options,
      onUpdate: onUpdate,
    );
  }

  /// Submits a task and waits for its result in one call.
  Future<ToolTask> run(
    String path, {
    Map<String, dynamic> fields = const {},
    List<BitmeshFile> files = const [],
    PollingOptions polling = const PollingOptions(),
    void Function(ToolTask task)? onUpdate,
  }) async {
    final task = await submit(path, fields: fields, files: files);
    onUpdate?.call(task);
    if (task.isCompleted) return task;
    if (task.taskId.isEmpty) {
      throw const BitmeshSerializationException(
        'The API did not return a task id for the tools request.',
      );
    }
    return waitFor(task.taskId, options: polling, onUpdate: onUpdate);
  }

  /// Fetches a tool result as text (unsigned `GET`).
  Future<String> fetchResult(String pathOrUrl) async =>
      (await _fetchPublic(pathOrUrl)).body;

  /// Fetches a tool result as bytes, e.g. a produced image or video.
  ///
  /// Pass a result link exactly as the API returned it: links may point at the
  /// API or straight at the tool provider's storage. A bare path is fetched
  /// from the API's base URL.
  Future<Uint8List> fetchResultBytes(String pathOrUrl) async =>
      (await _fetchPublic(pathOrUrl)).bodyBytes;

  /// `POST /tools/video/image-animate`: turns a still image into a short
  /// video. Returns a task straight away; poll it with [imageAnimateStatus]
  /// or [waitForImageAnimate].
  ///
  /// The image is sent base64-encoded inside the JSON body. [seconds] is the
  /// video length, 1 to 10. Set [test] to get a made-up task without running
  /// the tool or spending credits.
  Future<ToolTask> imageAnimate({
    required String model,
    required BitmeshFile image,
    required int seconds,
    String? prompt,
    String? aspectRatio,
    String? callbackUrl,
    bool test = false,
  }) async {
    if (seconds < 1 || seconds > 10) {
      throw const BitmeshArgumentException('seconds must be between 1 and 10.');
    }
    final bytes = await image.readBytes();
    return ToolTask.fromJson(await imageAnimateRaw({
      'model': model,
      'image': {'bytes_base64_encoded': base64Encode(bytes)},
      'seconds': seconds,
      if (prompt != null) 'prompt': prompt,
      if (aspectRatio != null) 'aspect_ratio': aspectRatio,
      if (callbackUrl != null) 'callback_url': callbackUrl,
      if (test) 'test': true,
    }));
  }

  /// `POST /tools/video/image-animate` with a raw JSON payload.
  Future<Map<String, dynamic>> imageAnimateRaw(Map<String, dynamic> payload) =>
      _transport.postJson('/tools/video/image-animate', payload);

  /// `GET /tools/video/image-animate/{task_id}`. On success the video links
  /// are in [ToolTask.outputUrls]. Pass [test] for a task created in test mode.
  Future<ToolTask> imageAnimateStatus(String taskId, {bool test = false}) async =>
      ToolTask.fromJson(await imageAnimateStatusRaw(
        taskId,
        query: test ? const {'test': '1'} : const {},
      ));

  /// `GET /tools/video/image-animate/{task_id}`, returning the raw body.
  Future<Map<String, dynamic>> imageAnimateStatusRaw(
    String taskId, {
    Map<String, String> query = const {},
  }) =>
      _transport.getJson(
        '/tools/video/image-animate/${Uri.encodeComponent(_requireId(taskId))}',
        query: query,
      );

  /// Polls [imageAnimateStatus] until the video is ready, failed or was
  /// cancelled.
  Future<ToolTask> waitForImageAnimate(
    String taskId, {
    bool test = false,
    PollingOptions options = const PollingOptions(interval: Duration(seconds: 5)),
    void Function(ToolTask task)? onUpdate,
  }) {
    final id = _requireId(taskId);
    return pollJob<ToolTask>(
      jobId: id,
      fetch: () => imageAnimateStatus(id, test: test),
      statusOf: (task) => task.status,
      errorOf: (task) => task.error,
      options: options,
      onUpdate: onUpdate,
    );
  }

  Future<BitmeshResponse> _fetchPublic(String pathOrUrl) {
    final trimmed = pathOrUrl.trim();
    if (trimmed.isEmpty) {
      throw const BitmeshArgumentException('Tools result path is required.');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return _transport.getPublicUri(uri);
    }
    return _transport.getPublic(trimmed);
  }

  String _requireId(String taskId) {
    final trimmed = taskId.trim();
    if (trimmed.isEmpty) {
      throw const BitmeshArgumentException('Task id is required.');
    }
    return trimmed;
  }
}
