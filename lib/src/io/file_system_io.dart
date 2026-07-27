import 'dart:io';

bool? fileExists(String path) => File(path).existsSync();

int? fileLength(String path) {
  final file = File(path);
  return file.existsSync() ? file.lengthSync() : null;
}
