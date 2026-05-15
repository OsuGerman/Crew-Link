import 'package:crew_link/core/geo/geo_distance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('haversineMeters', () {
    test('returns 0 for identical points', () {
      final d = haversineMeters(
        lat1: 52.52,
        lon1: 13.405,
        lat2: 52.52,
        lon2: 13.405,
      );
      expect(d, closeTo(0, 0.0001));
    });

    test('Berlin <-> Potsdam ~27km', () {
      // Brandenburger Tor -> Sanssouci
      final d = haversineMeters(
        lat1: 52.5163,
        lon1: 13.3777,
        lat2: 52.4044,
        lon2: 13.0383,
      );
      expect(d, greaterThan(25000));
      expect(d, lessThan(28000));
    });

    test('short distance ~111m per 0.001° latitude', () {
      final d = haversineMeters(
        lat1: 0,
        lon1: 0,
        lat2: 0.001,
        lon2: 0,
      );
      expect(d, closeTo(111.0, 1.0));
    });
  });

  group('bearingDegrees', () {
    test('due north is 0°', () {
      final b = bearingDegrees(
        lat1: 0,
        lon1: 0,
        lat2: 0.5,
        lon2: 0,
      );
      expect(b, closeTo(0, 0.001));
    });

    test('due east is 90°', () {
      final b = bearingDegrees(
        lat1: 0,
        lon1: 0,
        lat2: 0,
        lon2: 0.5,
      );
      expect(b, closeTo(90, 0.001));
    });

    test('due south is 180°', () {
      final b = bearingDegrees(
        lat1: 0,
        lon1: 0,
        lat2: -0.5,
        lon2: 0,
      );
      expect(b, closeTo(180, 0.001));
    });

    test('due west is 270°', () {
      final b = bearingDegrees(
        lat1: 0,
        lon1: 0,
        lat2: 0,
        lon2: -0.5,
      );
      expect(b, closeTo(270, 0.001));
    });

    test('wraps result into [0, 360)', () {
      final b = bearingDegrees(
        lat1: 0,
        lon1: 0,
        lat2: -0.001,
        lon2: -0.001,
      );
      expect(b, greaterThanOrEqualTo(0));
      expect(b, lessThan(360));
      // ~southwest -> ~225°
      expect(b, closeTo(225, 5));
    });
  });
}
