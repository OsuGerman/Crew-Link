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

  /// Obergrenze pro REST-Call. Großzügig genug für einen Render-Kaltstart
  /// (Free-Tier ~25–30 s), aber endlich: ein hängendes Backend (z. B.
  /// pausierte DB) löst statt eines ewigen Spinners einen [TimeoutException]
  /// aus, den die UI als „erneut versuchen" zeigt.
  static const requestTimeout = Duration(seconds: 40);

  Future<Convoy> createConvoy({
    required String name,
    required String authToken,
    double proximityWarningMeters = 500,
  }) async {
    final response = await _client
        .post(
          config.restBaseUrl.replace(path: '/convoys'),
          headers: _authHeaders(authToken),
          body: jsonEncode({
            'name': name,
            'proximityWarningMeters': proximityWarningMeters,
          }),
        )
        .timeout(requestTimeout);
    return _parseConvoy(response);
  }

  Future<Convoy> joinConvoy({
    required String inviteCode,
    required String authToken,
  }) async {
    final response = await _client
        .post(
          config.restBaseUrl.replace(path: '/convoys/join'),
          headers: _authHeaders(authToken),
          body: jsonEncode({'inviteCode': inviteCode}),
        )
        .timeout(requestTimeout);
    return _parseConvoy(response);
  }

  /// Re-fetches the convoy (roster refresh) so members who joined after you
  /// appear without waiting for their first GPS frame.
  Future<Convoy> getConvoy({
    required String convoyId,
    required String authToken,
  }) async {
    final response = await _client.get(
      config.restBaseUrl.replace(path: '/convoys/$convoyId'),
      headers: {'Authorization': 'Bearer $authToken'},
    ).timeout(requestTimeout);
    return _parseConvoy(response);
  }

  Future<void> leaveConvoy({
    required String convoyId,
    required String authToken,
  }) async {
    // No request body → must NOT send `Content-Type: application/json`, or
    // Fastify rejects it with FST_ERR_CTP_EMPTY_JSON_BODY before auth even runs.
    final response = await _client.delete(
      config.restBaseUrl.replace(path: '/convoys/$convoyId/membership'),
      headers: {'Authorization': 'Bearer $authToken'},
    ).timeout(requestTimeout);
    if (response.statusCode >= 400) {
      throw ConvoyApiException(response.statusCode, response.body);
    }
  }

  /// GDPR / Play account deletion — removes the user, their vehicle, their
  /// memberships and the convoys they own. Firebase Auth is deleted separately.
  Future<void> deleteAccount({required String authToken}) async {
    final response = await _client.delete(
      config.restBaseUrl.replace(path: '/users/me'),
      headers: {'Authorization': 'Bearer $authToken'},
    ).timeout(requestTimeout);
    if (response.statusCode >= 400) {
      throw ConvoyApiException(response.statusCode, response.body);
    }
  }

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Convoy _parseConvoy(http.Response response) {
    if (response.statusCode >= 400) {
      throw ConvoyApiException(response.statusCode, response.body);
    }
    final decoded = (jsonDecode(response.body) as Map).cast<String, Object?>();
    return Convoy.fromJson(decoded);
  }
}

class ConvoyApiException implements Exception {
  ConvoyApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'ConvoyApiException($statusCode): $body';
}
