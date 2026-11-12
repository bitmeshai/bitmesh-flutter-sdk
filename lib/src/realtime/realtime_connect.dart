/// Opens the WebSocket of a real-time transcription session.
///
/// It needs `dart:io`: browsers can't send the key header on a WebSocket, so
/// on the web connecting throws `BitmeshConfigurationException`.
library;

export 'realtime_connect_stub.dart'
    if (dart.library.io) 'realtime_connect_io.dart';
