import 'dart:convert';

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/features/vehicle/data/vehicle_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

VehicleApi _api(http.Response Function(http.BaseRequest req) handler) {
  return VehicleApi(
    config: ApiConfig.local(),
    client: MockClient((req) async => handler(req)),
  );
}

void main() {
  group('VehicleApi', () {
    test('getMyVehicle returns null when server returns null', () async {
      final api = _api((_) => http.Response('null', 200));
      final v = await api.getMyVehicle(authToken: 'tok');
      expect(v, isNull);
    });

    test('getMyVehicle parses a present vehicle', () async {
      final api = _api((_) => http.Response(
            jsonEncode({
              'id': 'v1',
              'make': 'Tesla',
              'model': 'Model 3',
              'year': 2024,
              'color': 'Rot',
            }),
            200,
          ));
      final v = await api.getMyVehicle(authToken: 'tok');
      expect(v!.make, 'Tesla');
      expect(v.year, 2024);
    });

    test('putMyVehicle sends body and parses response', () async {
      http.BaseRequest? captured;
      final api = _api((req) {
        captured = req;
        return http.Response(
          jsonEncode({
            'id': 'v2',
            'make': 'Porsche',
            'model': '911 GT3',
            'year': null,
            'color': null,
          }),
          200,
        );
      });
      final result = await api.putMyVehicle(
        authToken: 'tok',
        make: 'Porsche',
        model: '911 GT3',
      );
      expect(captured!.method, 'PUT');
      expect(captured!.url.path, '/vehicles/me');
      expect(captured!.headers['Authorization'], 'Bearer tok');
      final reqBody =
          jsonDecode((captured! as http.Request).body) as Map<String, Object?>;
      expect(reqBody['make'], 'Porsche');
      expect(reqBody['model'], '911 GT3');
      expect(reqBody.containsKey('year'), isFalse);
      expect(reqBody.containsKey('color'), isFalse);
      expect(result.id, 'v2');
    });

    test('putMyVehicle omits empty color', () async {
      http.BaseRequest? captured;
      final api = _api((req) {
        captured = req;
        return http.Response(
          jsonEncode({
            'id': 'v3',
            'make': 'Audi',
            'model': 'RS6',
            'year': 2022,
            'color': null,
          }),
          200,
        );
      });
      await api.putMyVehicle(
        authToken: 'tok',
        make: 'Audi',
        model: 'RS6',
        year: 2022,
        color: '',
      );
      final reqBody =
          jsonDecode((captured! as http.Request).body) as Map<String, Object?>;
      expect(reqBody['year'], 2022);
      expect(reqBody.containsKey('color'), isFalse);
    });

    test('error response is thrown as VehicleApiException', () async {
      final api = _api((_) => http.Response('boom', 500));
      await expectLater(
        api.getMyVehicle(authToken: 'tok'),
        throwsA(isA<VehicleApiException>()),
      );
    });

    test('deleteMyVehicle accepts 204 without throwing', () async {
      final api = _api((_) => http.Response('', 204));
      await api.deleteMyVehicle(authToken: 'tok');
    });

    test('putMyVehicle includes spec fields when provided', () async {
      http.BaseRequest? captured;
      final api = _api((req) {
        captured = req;
        return http.Response(
          jsonEncode({
            'id': 'v4',
            'make': 'BMW',
            'model': 'M3',
            'year': 2023,
            'color': null,
            'power_kw': 375,
            'drivetrain': 'RWD',
            'displacement': 2993,
            'transmission_type': 'manual',
          }),
          200,
        );
      });
      final result = await api.putMyVehicle(
        authToken: 'tok',
        make: 'BMW',
        model: 'M3',
        year: 2023,
        powerKw: 375,
        drivetrain: 'RWD',
        displacement: 2993,
        transmissionType: 'manual',
      );
      final reqBody =
          jsonDecode((captured! as http.Request).body) as Map<String, Object?>;
      expect(reqBody['power_kw'], 375);
      expect(reqBody['drivetrain'], 'RWD');
      expect(reqBody['displacement'], 2993);
      expect(reqBody['transmission_type'], 'manual');
      expect(result.powerKw, 375);
      expect(result.drivetrain, 'RWD');
      expect(result.displacement, 2993);
      expect(result.transmissionType, 'manual');
    });

    test('putMyVehicle omits spec fields when null', () async {
      http.BaseRequest? captured;
      final api = _api((req) {
        captured = req;
        return http.Response(
          jsonEncode({'id': 'v5', 'make': 'VW', 'model': 'Golf'}),
          200,
        );
      });
      await api.putMyVehicle(authToken: 'tok', make: 'VW', model: 'Golf');
      final reqBody =
          jsonDecode((captured! as http.Request).body) as Map<String, Object?>;
      expect(reqBody.containsKey('power_kw'), isFalse);
      expect(reqBody.containsKey('drivetrain'), isFalse);
      expect(reqBody.containsKey('displacement'), isFalse);
      expect(reqBody.containsKey('transmission_type'), isFalse);
    });
  });
}
