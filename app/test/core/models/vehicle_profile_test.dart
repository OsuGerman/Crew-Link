import 'package:crew_link/core/models/vehicle_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VehicleProfile', () {
    test('fromJson with all fields', () {
      final v = VehicleProfile.fromJson(const {
        'id': 'v1',
        'make': 'Tesla',
        'model': 'Model 3',
        'year': 2024,
        'color': 'Indigoblau',
      });
      expect(v.id, 'v1');
      expect(v.make, 'Tesla');
      expect(v.model, 'Model 3');
      expect(v.year, 2024);
      expect(v.color, 'Indigoblau');
    });

    test('fromJson with optional fields missing', () {
      final v = VehicleProfile.fromJson(const {
        'id': 'v2',
        'make': 'Porsche',
        'model': '911',
      });
      expect(v.year, isNull);
      expect(v.color, isNull);
    });

    test('toJson round-trips', () {
      const original = VehicleProfile(
        id: 'v3',
        make: 'BMW',
        model: 'M2',
        year: 2023,
        color: 'Schwarz',
      );
      final round = VehicleProfile.fromJson(original.toJson());
      expect(round, original);
    });

    test('headline includes year when present', () {
      const v = VehicleProfile(
        id: 'v', make: 'Audi', model: 'RS6', year: 2022,
      );
      expect(v.headline, 'Audi RS6 · 2022');
    });

    test('headline omits year when missing', () {
      const v = VehicleProfile(id: 'v', make: 'Audi', model: 'RS6');
      expect(v.headline, 'Audi RS6');
    });

    test('copyWith preserves untouched fields', () {
      const v = VehicleProfile(
        id: 'v', make: 'Tesla', model: 'Model 3',
        year: 2024, color: 'Rot',
      );
      final updated = v.copyWith(model: 'Model S');
      expect(updated.id, 'v');
      expect(updated.make, 'Tesla');
      expect(updated.model, 'Model S');
      expect(updated.year, 2024);
      expect(updated.color, 'Rot');
    });
  });
}
