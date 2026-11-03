import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/app_exception.dart';

/// Talks to the WoL relay script running on an always-on device at home.
class RelayClient {
  RelayClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> wake({required String host, required int port}) async {
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: AppConstants.relayWakePath,
    );
    final http.Response response;
    try {
      response =
          await _client.get(uri).timeout(AppConstants.relayRequestTimeout);
    } on TimeoutException {
      throw AppException(
        'The relay device ($host:$port) did not answer. Check that it is '
        'online, connected to Tailscale and running the relay script.',
      );
    } on SocketException {
      throw AppException(
        'Could not reach the relay device at $host:$port. Check that it is '
        'online, connected to Tailscale and running the relay script.',
      );
    } on http.ClientException catch (e) {
      throw AppException('Error contacting the relay device: ${e.message}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var body = response.body.trim();
      if (body.length > 200) body = '${body.substring(0, 200)}…';
      throw AppException(
        'The relay device answered with an error (HTTP ${response.statusCode})'
        '${body.isEmpty ? '' : ': $body'}',
      );
    }
  }

  void close() => _client.close();
}
