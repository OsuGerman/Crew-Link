import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';

/// HTTP-Status ab dem die Token-Route als Fehler gilt (4xx/5xx).
const _httpClientErrorFloor = 400;

/// Zugangsdaten für einen LiveKit-Raum — Antwort der Backend-Route
/// `POST /convoys/:convoyId/ptt-token` (backend/src/routes/ptt.ts).
class PttTokenResponse {
  const PttTokenResponse({
    required this.url,
    required this.token,
    required this.roomName,
  });

  factory PttTokenResponse.fromJson(Map<String, Object?> json) =>
      PttTokenResponse(
        url: json['url']! as String,
        token: json['token']! as String,
        roomName: json['roomName']! as String,
      );

  /// LiveKit-Server-URL (`wss://…`).
  final String url;

  /// Signiertes LiveKit-Access-Token für genau diesen Raum.
  final String token;

  /// Raumname (`convoy-<id>`) — für Logging/Debugging.
  final String roomName;
}

/// Fehler der Token-Route. [statusCode] 503 bedeutet: LiveKit ist auf dem
/// Server nicht konfiguriert (LIVEKIT_URL/KEY/SECRET fehlen) — das ist das
/// Signal für den P2P-Fallback, kein harter Fehler.
class PttTokenException implements Exception {
  PttTokenException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'PttTokenException($statusCode): $body';
}

/// Holt LiveKit-Tokens vom Backend — gleiche Base-URL und Bearer-Auth wie
/// die übrigen REST-Calls (ConvoyApi). [tokenProvider] liefert pro Aufruf
/// einen FRISCHEN Firebase-ID-Token (siehe freshAuthTokenProvider), damit
/// ein PTT-Druck nach >1 h Fahrt nicht an einem abgelaufenen Token scheitert.
class PttTokenFetcher {
  PttTokenFetcher({
    required this.config,
    required Future<String> Function() tokenProvider,
    http.Client? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? http.Client();

  final ApiConfig config;
  final Future<String> Function() _tokenProvider;
  final http.Client _client;

  /// Fordert ein LiveKit-Token für [convoyId] an.
  ///
  /// Bodyloser POST → bewusst KEIN `Content-Type: application/json`, sonst
  /// lehnt Fastify die Anfrage mit FST_ERR_CTP_EMPTY_JSON_BODY ab bevor die
  /// Auth überhaupt läuft (gleiches Muster wie ConvoyApi.leaveConvoy).
  Future<PttTokenResponse> fetchToken(String convoyId) async {
    final authToken = await _tokenProvider();
    final response = await _client.post(
      config.restBaseUrl.replace(path: '/convoys/$convoyId/ptt-token'),
      headers: {'Authorization': 'Bearer $authToken'},
    );
    if (response.statusCode >= _httpClientErrorFloor) {
      throw PttTokenException(response.statusCode, response.body);
    }
    final decoded = (jsonDecode(response.body) as Map).cast<String, Object?>();
    return PttTokenResponse.fromJson(decoded);
  }
}
