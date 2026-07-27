import 'package:meta/meta.dart';

import 'json_utils.dart';

/// Parameters for `POST /image`.
@immutable
class ImageRequest {
  const ImageRequest({
    required this.prompt,
    required this.model,
    this.width,
    this.height,
    this.steps,
    this.seed,
    this.n,
    this.negativePrompt,
    this.referenceImages,
    this.extra = const {},
  });

  final String prompt;
  final String model;
  final int? width;
  final int? height;

  /// Inference steps. More steps, slower and usually cleaner.
  final int? steps;

  /// Seed for reproducible output.
  final int? seed;

  /// How many images to generate.
  final int? n;

  final String? negativePrompt;

  /// URLs used as input for image-to-image workflows.
  final List<String>? referenceImages;

  /// Extra body fields, merged last.
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        ...compact({
          'prompt': prompt,
          'model': model,
          'width': width,
          'height': height,
          'steps': steps,
          'seed': seed,
          'n': n,
          'negative_prompt': negativePrompt,
          'reference_images': referenceImages,
        }),
        ...extra,
      };
}

/// A single generated image.
@immutable
class GeneratedImage {
  const GeneratedImage({this.url, this.objectId, this.base64, this.raw = const {}});

  /// Direct URL, when the API returned one.
  final String? url;

  /// Object id, resolvable through `/imgrslt/{objectId}`.
  final String? objectId;

  /// Inline base64 payload, when requested.
  final String? base64;

  final Map<String, dynamic> raw;

  factory GeneratedImage.fromJson(Map<String, dynamic> json) => GeneratedImage(
        url: asString(pick(json, ['url', 'image_url'])),
        objectId: asString(pick(json, ['object_id', 'objectId', 'id'])),
        base64: asString(pick(json, ['b64_json', 'base64'])),
        raw: json,
      );

  /// Absolute URL to fetch this image, given the client's base URL.
  ///
  /// Returns `null` when the API provided neither a URL nor an object id.
  String? resolveUrl(String baseUrl) {
    if (url != null && url!.isNotEmpty) {
      if (url!.startsWith('http')) return url;
      return '${baseUrl.replaceAll(RegExp(r'/+$'), '')}'
          '/${url!.replaceAll(RegExp(r'^/+'), '')}';
    }
    if (objectId != null && objectId!.isNotEmpty) {
      return '${baseUrl.replaceAll(RegExp(r'/+$'), '')}'
          '/imgrslt/${Uri.encodeComponent(objectId!)}';
    }
    return null;
  }

  @override
  String toString() => 'GeneratedImage(url: $url, objectId: $objectId)';
}

/// Response of `POST /image`.
@immutable
class ImageResponse {
  const ImageResponse({required this.images, required this.raw, this.model});

  final List<GeneratedImage> images;
  final String? model;

  /// The unmodified response body.
  final Map<String, dynamic> raw;

  factory ImageResponse.fromJson(Map<String, dynamic> json) => ImageResponse(
        images: asMapList(pick(json, ['data', 'images', 'output']))
            .map(GeneratedImage.fromJson)
            .toList(growable: false),
        model: asString(json['model']),
        raw: json,
      );

  GeneratedImage? get first => images.isEmpty ? null : images.first;

  @override
  String toString() => 'ImageResponse(${images.length} image(s))';
}
