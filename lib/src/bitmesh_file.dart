import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'exceptions.dart';
import 'io/file_system.dart';

/// A file to upload, sourced either from disk or from memory.
///
/// In-memory uploads ([BitmeshFile.fromBytes]) are the portable option: they
/// work on Flutter web, where there is no filesystem, and on data you produced
/// without ever writing it to disk.
class BitmeshFile {
  BitmeshFile._({
    required this.field,
    this.path,
    this.bytes,
    String? filename,
    String? contentType,
  })  : filename = filename ?? (path == null ? null : _basename(path)),
        contentType = contentType ??
            _inferContentType(filename ?? (path == null ? null : _basename(path)));

  /// A file read from disk. Not supported on the web.
  factory BitmeshFile.fromPath(
    String path, {
    String field = 'file',
    String? filename,
    String? contentType,
  }) {
    if (path.trim().isEmpty) {
      throw const BitmeshArgumentException('File path must not be empty.');
    }
    return BitmeshFile._(
      field: field,
      path: path,
      filename: filename,
      contentType: contentType,
    );
  }

  /// A file held in memory. Works on every platform.
  factory BitmeshFile.fromBytes(
    List<int> bytes, {
    required String filename,
    String field = 'file',
    String? contentType,
  }) {
    return BitmeshFile._(
      field: field,
      bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      filename: filename,
      contentType: contentType,
    );
  }

  /// Multipart form field name, e.g. `audio` or `image`.
  final String field;

  /// Source path, when created with [BitmeshFile.fromPath].
  final String? path;

  /// Source bytes, when created with [BitmeshFile.fromBytes].
  final Uint8List? bytes;

  /// Name reported to the server.
  final String? filename;

  /// MIME type, inferred from the extension when not given explicitly.
  final String? contentType;

  /// Copies this file with a different form field name.
  BitmeshFile withField(String field) => BitmeshFile._(
        field: field,
        path: path,
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );

  /// Throws if a path-based file is known to be missing.
  void validate() {
    final path = this.path;
    if (path == null) return;
    if (fileExists(path) == false) {
      throw BitmeshArgumentException(
        'File does not exist for field "$field": $path',
      );
    }
  }

  Future<http.MultipartFile> toMultipartFile() async {
    validate();
    final mediaType = contentType == null ? null : MediaType.parse(contentType!);
    final bytes = this.bytes;
    if (bytes != null) {
      return http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: filename,
        contentType: mediaType,
      );
    }
    return http.MultipartFile.fromPath(
      field,
      path!,
      filename: filename,
      contentType: mediaType,
    );
  }

  @override
  String toString() => 'BitmeshFile(field: $field, '
      '${path != null ? 'path: $path' : 'bytes: ${bytes?.length ?? 0}'}, '
      'contentType: $contentType)';

  static String _basename(String path) {
    final segments =
        path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? path : segments.last;
  }

  static const Map<String, String> _mimeTypes = {
    'aac': 'audio/aac',
    'flac': 'audio/flac',
    'm4a': 'audio/mp4',
    'mp3': 'audio/mpeg',
    'oga': 'audio/ogg',
    'ogg': 'audio/ogg',
    'opus': 'audio/opus',
    'wav': 'audio/wav',
    'weba': 'audio/webm',
    'bmp': 'image/bmp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'jpeg': 'image/jpeg',
    'jpg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'json': 'application/json',
    'txt': 'text/plain',
  };

  static String? _inferContentType(String? filename) {
    if (filename == null) return null;
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return null;
    return _mimeTypes[filename.substring(dot + 1).toLowerCase()];
  }
}
