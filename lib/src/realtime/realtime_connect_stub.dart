import '../exceptions.dart';
import 'realtime_session.dart';

Future<RealtimeSocket> connectRealtimeSocket(
  Uri uri,
  Map<String, String> headers,
  Duration timeout,
) =>
    throw const BitmeshConfigurationException(
      'Real-time transcription needs dart:io (Android, iOS, desktop or a '
      'server). Browsers cannot send the key header on a WebSocket, so connect '
      'from your server instead.',
    );
