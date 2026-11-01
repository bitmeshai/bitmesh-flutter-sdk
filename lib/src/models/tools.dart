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
      outputUrls: _outputUrls(json),
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

  /// Result locations, read from the places the tools put them first:
  /// `data.image_url` (background removal), `output.image_url` (try-on),
  /// `data.images` and `data.output_videos[].url` (image animation). Anything
  /// else that looks like a result is collected after those.
  static List<String> _outputUrls(Map<String, dynamic> json) {
    final data = asMap(json['data']);
    final output = asMap(json['output']);
    final known = <String>[
      if (asString(data?['image_url']) case final url? when url.isNotEmpty) url,
      if (asString(output?['image_url']) case final url? when url.isNotEmpty)
        url,
      ...?_strings(data?['images']),
      ...asMapList(data?['output_videos'])
          .map((video) => asString(video['url']))
          .whereType<String>(),
    ];
    return {...known, ..._collectUrls(json)}.toList(growable: false);
  }

  static List<String>? _strings(Object? value) => value is List
      ? value.whereType<String>().where((s) => s.isNotEmpty).toList()
      : null;

  /// Keys that hold addresses but never a result: the relay address the API
  /// registers for provider callbacks, and echoed request inputs.
  static const _notResults = {'callback_url', 'inputs'};

  /// Walks the payload collecting anything that looks like a result location.
  static List<String> _collectUrls(Object? node, [int depth = 0]) {
    if (depth > 6) return const [];
    final found = <String>[];

    if (node is Map) {
      node.forEach((key, value) {
        final name = key.toString().toLowerCase();
        if (_notResults.contains(name)) return;
        final named = name.contains('url') ||
            name.contains('image') ||
            name.contains('video') ||
            name.contains('file_path');
        if (value is String && value.isNotEmpty && named) {
          found.add(value);
        } else if (value is List && named) {
          found.addAll(value.whereType<String>().where((s) => s.isNotEmpty));
          found.addAll(_collectUrls(value, depth + 1));
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
