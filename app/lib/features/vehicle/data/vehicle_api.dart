import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/models/vehicle_mod.dart';
import '../../../core/models/vehicle_profile.dart';

/// REST client for `/vehicles/me`. Talks to the backend defined in
/// `backend/src/routes/vehicles.ts`. The single-vehicle invariant
/// (one vehicle per user) is enforced on the server — PUT replaces
/// any existing entry. GET returns the vehicle or `null`.
class VehicleApi {
  VehicleApi({required this.config, http.Client? client})
      : _client = client ?? http.Client();

  final ApiConfig config;
  final http.Client _client;

  Future<VehicleProfile?> getMyVehicle({required String authToken}) async {
    final response = await _client.get(
      config.restBaseUrl.replace(path: '/vehicles/me'),
      headers: _authHeaders(authToken),
    );
    _ensureOk(response);
    if (response.body.isEmpty || response.body == 'null') return null;
    final decoded = jsonDecode(response.body);
    if (decoded == null) return null;
    return VehicleProfile.fromJson((decoded as Map).cast<String, Object?>());
  }

  Future<VehicleProfile> putMyVehicle({
    required String authToken,
    required String make,
    required String model,
    int? year,
    String? color,
    int? powerKw,
    String? drivetrain,
    int? displacement,
    String? transmissionType,
    List<VehicleMod> mods = const <VehicleMod>[],
  }) async {
    final body = <String, Object?>{
      'make': make,
      'model': model,
    };
    if (year != null) body['year'] = year;
    if (color != null && color.isNotEmpty) body['color'] = color;
    if (powerKw != null) body['power_kw'] = powerKw;
    if (drivetrain != null && drivetrain.isNotEmpty) {
      body['drivetrain'] = drivetrain;
    }
    if (displacement != null) body['displacement'] = displacement;
    if (transmissionType != null && transmissionType.isNotEmpty) {
      body['transmission_type'] = transmissionType;
    }
    body['mods'] = mods.map((m) => m.toPutBody()).toList(growable: false);
    final response = await _client.put(
      config.restBaseUrl.replace(path: '/vehicles/me'),
      headers: _authHeaders(authToken, withJson: true),
      body: jsonEncode(body),
    );
    _ensureOk(response);
    final decoded = (jsonDecode(response.body) as Map).cast<String, Object?>();
    return VehicleProfile.fromJson(decoded);
  }

  Future<void> deleteMyVehicle({required String authToken}) async {
    final response = await _client.delete(
      config.restBaseUrl.replace(path: '/vehicles/me'),
      headers: _authHeaders(authToken),
    );
    if (response.statusCode >= 400) {
      throw VehicleApiException(response.statusCode, response.body);
    }
  }

  Map<String, String> _authHeaders(String token, {bool withJson = false}) {
    return {
      'Authorization': 'Bearer $token',
      if (withJson) 'Content-Type': 'application/json',
    };
  }

  void _ensureOk(http.Response response) {
    if (response.statusCode >= 400) {
      throw VehicleApiException(response.statusCode, response.body);
    }
  }
}

class VehicleApiException implements Exception {
  VehicleApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'VehicleApiException($statusCode): $body';
}
