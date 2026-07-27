import 'package:meta/meta.dart';

import 'job_status.dart';
import 'json_utils.dart';

/// A keyframe reference for video generation.
@immutable
class VideoFrameImage {
  const VideoFrameImage({required this.inputImage, required this.frame});

  /// URL of the image to use.
  final String inputImage;

  /// Frame position this image applies to.
  final int frame;

  Map<String, dynamic> toJson() => {'input_image': inputImage, 'frame': frame};
}

/// Parameters for `POST /video`.
@immutable
class VideoRequest {
  const VideoRequest({
    required this.prompt,
    required this.model,
    this.width,
    this.height,
    this.seconds,
    this.fps,
    this.steps,
    this.seed,
    this.guidanceScale,
    this.outputFormat,
    this.outputQuality,
    this.negativePrompt,
    this.frameImages,
    this.referenceImages,
    this.extra = const {},
  });

  /// 1–32000 characters.
  final String prompt;
  final String model;
  final int? width;
  final int? height;

  /// Duration, expressed the way the chosen provider expects (e.g. `'5'`).
  final String? seconds;

  final int? fps;

  /// Inference steps, 10–50.
  final int? steps;

  final int? seed;
  final double? guidanceScale;

  /// `MP4` or `WEBM`.
  final String? outputFormat;

  final int? outputQuality;
  final String? negativePrompt;
  final List<VideoFrameImage>? frameImages;
  final List<String>? referenceImages;

  /// Extra body fields, merged last.
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        ...compact({
          'prompt': prompt,
          'model': model,
          'width': width,
          'height': height,
          'seconds': seconds,
          'fps': fps,
          'steps': steps,
          'seed': seed,
          'guidance_scale': guidanceScale,
          'output_format': outputFormat,
          'output_quality': outputQuality,
          'negative_prompt': negativePrompt,
          'frame_images': frameImages?.map((f) => f.toJson()).toList(),
          'reference_images': referenceImages,
        }),
        ...extra,
      };
}

/// A video generation job, as returned by `POST /video` and `GET /video/{id}`.
@immutable
class VideoJob {
  const VideoJob({
    required this.id,
    required this.status,
    required this.raw,
    this.rawStatus,
    this.videoUrl,
    this.width,
    this.height,
    this.createdAt,
    this.completedAt,
    this.cost,
    this.error,
  });

  final String id;
  final JobStatus status;

  /// Status string exactly as reported by the API.
  final String? rawStatus;

  /// Output URL, present once the job completes.
  final String? videoUrl;

  final int? width;
  final int? height;
  final DateTime? createdAt;
  final DateTime? completedAt;

  /// Credits charged, when reported.
  final double? cost;

  /// Failure detail, when the job failed.
  final String? error;

  /// The unmodified response body.
  final Map<String, dynamic> raw;

  factory VideoJob.fromJson(Map<String, dynamic> json) {
    final outputs = asMap(pick(json, ['outputs', 'output', 'result'])) ?? const {};
    final rawStatus = asString(pick(json, ['status', 'state']));
    final error = asMap(json['error']);

    return VideoJob(
      id: asString(pick(json, ['id', 'job_id', 'task_id'])) ?? '',
      status: JobStatus.parse(rawStatus),
      rawStatus: rawStatus,
      videoUrl: asString(pick(outputs, ['video_url', 'url'])) ??
          asString(pick(json, ['video_url', 'url'])),
      width: asInt(json['width']),
      height: asInt(json['height']),
      createdAt: asDateTime(pick(json, ['created_at', 'created'])),
      completedAt: asDateTime(pick(json, ['completed_at', 'finished_at'])),
      cost: asDouble(pick(json, ['cost', 'credits', 'total_cost'])),
      error: error != null
          ? asString(error['message'])
          : asString(pick(json, ['error', 'error_message', 'failure_reason'])),
      raw: json,
    );
  }

  bool get isCompleted => status.isSuccess;
  bool get isTerminal => status.isTerminal;

  @override
  String toString() =>
      'VideoJob($id, status: ${rawStatus ?? status.name}, url: $videoUrl)';
}
