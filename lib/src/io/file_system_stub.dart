/// Returns `null`: existence cannot be determined without `dart:io`.
bool? fileExists(String path) => null;

/// There is no filesystem without `dart:io`; use `BitmeshFile.fromBytes`.
Future<List<int>> readFileBytes(String path) => throw UnsupportedError(
    'Reading files from a path needs dart:io. Use BitmeshFile.fromBytes on the web.');

/// Returns the file size, or `null` when it cannot be determined.
int? fileLength(String path) => null;
