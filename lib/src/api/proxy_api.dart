import 'dart:convert';

import '../exceptions.dart';
import '../http/bitmesh_transport.dart';
import '../http/server_sent_events.dart';

/// The provider proxy: `/v2/proxy/{provider}/{path}`, for proxy keys.
///
/// Send the request you would send to the provider, minus its own
/// `Authorization` or `x-api-key` header: Bitmesh adds the stored provider key.
/// Bodies and replies pass through unchanged.
///
/// ```dart
/// final reply = await client.proxy.post('openai', 'v1/chat/completions', {
///   'model': 'gpt-4o-mini',
///   'messages': [{'role': 'user', 'content': 'Hello'}],
/// });
/// ```
class ProxyApi {
  ProxyApi(this._transport);

  final BitmeshTransport _transport;

  static final RegExp _provider = RegExp(r'^[a-z0-9-]+$');

  /// `POST` a JSON body and return the provider's JSON reply.
  ///
  /// [headers] carries provider headers that select options, such as
  /// `anthropic-version`.
  Future<Map<String, dynamic>> post(
    String provider,
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final response = await send(provider, path,
        method: 'POST', body: body, headers: headers);
    return response.json();
  }

  /// `GET` a provider path, such as `v1/models`, and return its JSON reply.
  Future<Map<String, dynamic>> get(
    String provider,
    String path, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final response =
        await send(provider, path, query: query, headers: headers);
    return response.json();
  }

  /// Any request, returning the whole response, its headers included
  /// ([BitmeshResponse.requestId], the provider's rate-limit headers).
  ///
  /// A non-2xx answer throws a [BitmeshApiException] holding the body, from
  /// Bitmesh or passed through from the provider.
  Future<BitmeshResponse> send(
    String provider,
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) =>
      _transport.send(
        method,
        _path(provider, path),
        body: body == null ? null : jsonEncode(body),
        query: query,
        headers: headers,
      );

  /// `POST` with `"stream": true` and return the provider's server-sent
  /// events as they arrive. OpenAI-style streams end with an event whose
  /// [ServerSentEvent.isDone] is true; Anthropic's name each event in
  /// [ServerSentEvent.event].
  Stream<ServerSentEvent> stream(
    String provider,
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) =>
      _transport.stream(
        'POST',
        _path(provider, path),
        body: jsonEncode({...body, 'stream': true}),
        headers: headers,
      );

  String _path(String provider, String path) {
    final name = provider.trim().toLowerCase();
    if (!_provider.hasMatch(name)) {
      throw BitmeshArgumentException(
        'Invalid provider "$provider". Use the provider\'s name as in the '
        'docs, e.g. "openai", "anthropic" or "together".',
      );
    }
    return '/proxy/$name/${path.trim().replaceAll(RegExp(r'^/+'), '')}';
  }
}
