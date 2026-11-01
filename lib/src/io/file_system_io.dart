import 'dart:io';

bool? fileExists(String path) => File(path).existsSync();

/// Reads a whole file into memory.
Future<List<int>> readFileBytes(String path) => File(path).readAsBytes();

int? fileLength(String path) {
  final file = File(path);
  return file.existsSync() ? file.lengthSync() : null;
}
