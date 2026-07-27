import 'dart:typed_data';

import '../exceptions.dart';
import '../http/bitmesh_transport.dart';
import '../models/image.dart';

/// `POST /image` — image generation, plus helpers for fetching results.
class ImageApi {
  ImageApi(this._transport, this._baseUrl);

  final BitmeshTransport _transport;
  final String _baseUrl;

  /// Typed image generation.
  Future<ImageResponse> generate(ImageRequest request) async {
    final json = await _transport.postJson('/image', request.toJson());
    return ImageResponse.fromJson(json);
  }

  /// Raw request/response.
  Future<Map<String, dynamic>> generateRaw(Map<String, dynamic> payload) =>
      _transport.postJson('/image', payload);

  /// Alias for [generateRaw], so `client.images({...})` works.
  Future<Map<String, dynamic>> call(Map<String, dynamic> payload) =>
      generateRaw(payload);

  /// Absolute URL for an `/imgrslt/{objectId}` result. No auth required, so it
  /// can be handed straight to `Image.network`.
  String resultUrl(String objectId) {
    final trimmed = objectId.trim();
    if (trimmed.isEmpty) {
      throw const BitmeshArgumentException('Image object id is required.');
    }
    return '${_baseUrl.replaceAll(RegExp(r'/+$'), '')}'
        '/imgrslt/${Uri.encodeComponent(trimmed)}';
  }

  /// Downloads a generated image, e.g. for `Image.memory` or local caching.
  ///
  /// [objectIdOrPath] accepts a bare object id, an `/imgrslt/...` path, or an
  /// absolute URL on the configured host.
  Future<Uint8List> download(String objectIdOrPath) async {
    final trimmed = objectIdOrPath.trim();
    if (trimmed.isEmpty) {
      throw const BitmeshArgumentException('Image object id or path is required.');
    }

    final path = trimmed.startsWith('http')
        ? Uri.parse(trimmed).path
        : (trimmed.contains('/') ? trimmed : 'imgrslt/$trimmed');

    final response = await _transport.getPublic(path);
    return response.bodyBytes;
  }
}
