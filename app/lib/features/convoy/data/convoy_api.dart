import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/models/convoy.dart';

/// REST client for convoy CRUD. Rule: no real-time data over REST.
class ConvoyApi {
  ConvoyApi({required this.config, http.Client? client})
      : _client = client ?? http.Client();

  final ApiConfig config;
  final http.Client _client;

  Future<Convoy> createConvoy({
    required String name,
    required String authToken,
    double proximityWarningMeters = 500,
  }) async {
    final response = await _client.post(
      config.restBaseUrl.replace(path: '/convoys'),
      headers: _authHeaders(authToken),
      body: jsonEncode({
        'name': name,
        'proximityWarningMeters': proximityWarningMeters,
      }),
    );
    return _parseConvoy(response);
  }

  Future<Convoy> joinConvoy({
    required String inviteCode,
    required String authToken,
  }) async {
    final response = await _client.post(
      config.restBaseUrl.replace(path: '/convoys/join'),
      headers: _authHeaders(authToken),
      body: jsonEncode({'inviteCode': inviteCode}),
    );
    return _parseConvoy(response);
  }

  Future<void> leaveConvoy({
    required String convoyId,
    required String authToken,
  }) async {
    final response = await _client.delete(
      config.restBaseUrl.replace(path: '/convoys/$convoyId/membership'),
      headers: _authHeaders(authToken),
    );
    if (response.statusCode >= 400) {
      throw _ConvoyApiException(response.statusCode, response.body);
    }
  }

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Convoy _parseConvoy(http.Response response) {
    if (response.statusCode >= 400) {
      throw _ConvoyApiException(response.statusCode, response.body);
    }
    final decoded = (jsonDecode(response.body) as Map).cast<String, Object?>();
    return Convoy.fromJson(decoded);
  }
}

class _ConvoyApiException implements Exception {
  _ConvoyApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'ConvoyApiException($statusCode): $body';
}
