import 'package:meta/meta.dart';

import 'job_status.dart';
import 'json_utils.dart';

/// An asynchronous `/tools` task.
///
/// The tools endpoints are less uniform than the rest of the API, so this model
/// stays deliberately thin: it locates the task id, status and any output URLs,
/// and hands you [raw] for everything else.
@immutable
class ToolTask {
  const ToolTask({
    required this.taskId,
    required this.status,
    required this.raw,
    this.rawStatus,
    this.outputUrls = const [],
    this.error,
  });

  final String taskId;
  final JobStatus status;

  /// Status string exactly as reported by the API.
  final String? rawStatus;

  /// Result URLs or paths discovered in the payload.
  final List<String> outputUrls;

  /// Failure detail, when the task failed.
  final String? error;

  /// The unmodified response body.
  final Map<String, dynamic> raw;

  factory ToolTask.fromJson(Map<String, dynamic> json) {
    final data = asMap(pick(json, ['data', 'result', 'output'])) ?? const {};
    final rawStatus = asString(pick(json, ['status', 'task_status', 'state'])) ??
        asString(pick(data, ['status', 'task_status']));
    final error = asMap(json['error']);

    return ToolTask(
      taskId: asString(pick(json, ['task_id', 'taskId', 'id'])) ??
          asString(pick(data, ['task_id', 'taskId', 'id'])) ??
          '',
      status: JobStatus.parse(rawStatus),
      rawStatus: rawStatus,
      outputUrls: _collectUrls(json),
      error: error != null
          ? asString(error['message'])
          : asString(pick(json, ['error', 'message', 'error_message'])),
      raw: json,
    );
  }

  bool get isCompleted => status.isSuccess;
  bool get isTerminal => status.isTerminal;

  /// First output URL, if any.
  String? get outputUrl => outputUrls.isEmpty ? null : outputUrls.first;

  @override
  String toString() =>
      'ToolTask($taskId, status: ${rawStatus ?? status.name}, '
      'outputs: ${outputUrls.length})';

  /// Walks the payload collecting anything that looks like a result location.
  static List<String> _collectUrls(Object? node, [int depth = 0]) {
    if (depth > 6) return const [];
    final found = <String>[];

    if (node is Map) {
      node.forEach((key, value) {
        final name = key.toString().toLowerCase();
        if (value is String &&
            value.isNotEmpty &&
            (name.contains('url') ||
                name.contains('image') ||
                name.contains('file_path'))) {
          found.add(value);
        } else {
          found.addAll(_collectUrls(value, depth + 1));
        }
      });
    } else if (node is List) {
      for (final item in node) {
        found.addAll(_collectUrls(item, depth + 1));
      }
    }

    return found.toSet().toList(growable: false);
  }
}
