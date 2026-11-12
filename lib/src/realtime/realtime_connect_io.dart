import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../exceptions.dart';
import 'realtime_session.dart';

/// Performs the WebSocket handshake itself, so that a refused one (`401`,
/// `402`, `422`, `429`, ...) comes back as the API's status and JSON body,
/// which `WebSocket.connect` would hide.
Future<RealtimeSocket> connectRealtimeSocket(
  Uri uri,
  Map<String, String> headers,
  Duration timeout,
) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.openUrl('GET', uri).timeout(timeout);
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    final random = Random.secure();
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Key',
          base64.encode(List<int>.generate(16, (_) => random.nextInt(256))));

    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.switchingProtocols) {
      final body = await response
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(timeout);
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) =>
          responseHeaders[name.toLowerCase()] = values.join(','));
      throw BitmeshApiException.fromResponse(
        response.statusCode,
        body,
        headers: responseHeaders,
      );
    }

    final socket = await response.detachSocket();
    return _IoRealtimeSocket(
        WebSocket.fromUpgradedSocket(socket, serverSide: false));
  } on BitmeshException {
    rethrow;
  } on TimeoutException {
    throw BitmeshTimeoutException(
      timeout,
      detail: 'The real-time transcription connection timed out.',
    );
  } on Object catch (e) {
    throw BitmeshNetworkException(
      'Could not open the real-time transcription connection.',
      cause: e,
    );
  } finally {
    client.close();
  }
}

class _IoRealtimeSocket implements RealtimeSocket {
  _IoRealtimeSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get messages => _socket;

  @override
  void add(Object data) => _socket.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;
}
