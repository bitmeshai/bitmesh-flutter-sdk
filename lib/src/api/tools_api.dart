import 'dart:typed_data';

import '../bitmesh_file.dart';
import '../exceptions.dart';
import '../http/bitmesh_transport.dart';
import '../models/tools.dart';
import '../polling.dart';

/// `/tools/*` — task-based image utilities.
///
/// These endpoints submit work asynchronously: you get a `task_id`, poll
/// [queryAsyncTaskResult] (or let [waitFor] do it), then fetch the output with
/// [fetchResult].
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
  Future<String> fetchResult(String pathOrUrl) async {
    final response = await _transport.getPublic(_resultPath(pathOrUrl));
    return response.body;
  }

  /// Fetches a tool result as bytes, e.g. a produced image.
  Future<Uint8List> fetchResultBytes(String pathOrUrl) async {
    final response = await _transport.getPublic(_resultPath(pathOrUrl));
    return response.bodyBytes;
  }

  /// Raw multipart submit.
  Future<Map<String, dynamic>> submitRaw(
    String path, {
    Map<String, dynamic> fields = const {},
    Map<String, String> filePaths = const {},
  }) =>
      _transport.postMultipart(
        path,
        fields: fields,
        files: filePaths.entries
            .map((e) => BitmeshFile.fromPath(e.value, field: e.key))
            .toList(),
      );

  /// Raw task polling.
  Future<Map<String, dynamic>> queryAsyncTaskResultRaw(String taskId) =>
      _transport.postJson(
        '/tools/query-async-task-result',
        {'task_id': _requireId(taskId)},
      );

  String _resultPath(String pathOrUrl) {
    final trimmed = pathOrUrl.trim();
    if (trimmed.isEmpty) {
      throw const BitmeshArgumentException('Tools result path is required.');
    }
    return trimmed.startsWith('http') ? Uri.parse(trimmed).path : trimmed;
  }

  String _requireId(String taskId) {
    final trimmed = taskId.trim();
    if (trimmed.isEmpty) {
      throw const BitmeshArgumentException('Task id is required.');
    }
    return trimmed;
  }
}
