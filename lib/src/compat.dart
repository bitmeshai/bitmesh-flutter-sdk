import 'bitmesh_client.dart';
import 'bitmesh_file.dart';

/// Raw, map-in/map-out methods mirroring the pre-package `BitmeshClient`.
///
/// These exist so an app can drop the package in without rewriting call sites:
/// change the import, and `client.chat(...)`, `client.getVideo(...)` and
/// friends keep working. New code should prefer the typed APIs
/// (`client.chat.create`, `client.video.generate`, ...).
extension BitmeshRawApi on BitmeshClient {
  /// `POST /chat` with a raw payload.
  Future<Map<String, dynamic>> chatRaw(Map<String, dynamic> payload) =>
      chat.createRaw(payload);

  /// `POST /image` with a raw payload.
  Future<Map<String, dynamic>> imageRaw(Map<String, dynamic> payload) =>
      images.generateRaw(payload);

  /// `POST /video` with a raw payload.
  Future<Map<String, dynamic>> videoRaw(Map<String, dynamic> payload) =>
      video.createRaw(payload);

  /// `GET /video/{id}`.
  Future<Map<String, dynamic>> getVideo(
    String id, {
    Map<String, String> query = const {},
  }) =>
      video.getRaw(id, query: query);

  /// `POST /transcribe-recorded` with a local audio file.
  Future<Map<String, dynamic>> transcribeFile(
    String audioFilePath, {
    Map<String, dynamic> fields = const {},
  }) =>
      transcription.createRaw(audioFilePath, fields: fields);

  /// `GET /transcribe-recorded/{id}`.
  Future<Map<String, dynamic>> getTranscribeRecorded(
    String id, {
    Map<String, String> query = const {},
  }) =>
      transcription.getRaw(id, query: query);

  /// `POST /tools/general/background-removal`.
  Future<Map<String, dynamic>> toolsGeneralBackgroundRemoval(
    Map<String, dynamic> fields,
    String imagePath,
  ) =>
      tools.submitRaw(
        '/tools/general/background-removal',
        fields: fields,
        filePaths: {'image': imagePath},
      );

  /// `POST /tools/portrait/try-on-clothes`.
  Future<Map<String, dynamic>> toolsPortraitTryOnClothes(
    Map<String, dynamic> fields,
    Map<String, String> files,
  ) =>
      tools.submitRaw(
        '/tools/portrait/try-on-clothes',
        fields: fields,
        filePaths: files,
      );

  /// `POST /tools/query-async-task-result`.
  Future<Map<String, dynamic>> toolsQueryAsyncTaskResult(String taskId) =>
      tools.queryAsyncTaskResultRaw(taskId);

  /// Unsigned `GET` of a tool result, returned as text.
  Future<String> getToolsResult(String path) => tools.fetchResult(path);

  /// `POST /tools/*` with in-memory or on-disk uploads.
  Future<Map<String, dynamic>> toolsSubmitRaw(
    String path, {
    Map<String, dynamic> fields = const {},
    List<BitmeshFile> files = const [],
  }) =>
      transport.postMultipart(path, fields: fields, files: files);
}
