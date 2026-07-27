/// Platform-conditional filesystem probing.
///
/// On the web there is no filesystem, so `fileExists` returns `null`
/// ("unknown") and path-based uploads fail later with a clear error from
/// `package:http`.
library;

export 'file_system_stub.dart' if (dart.library.io) 'file_system_io.dart';
