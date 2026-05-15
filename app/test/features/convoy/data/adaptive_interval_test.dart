import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/data/adaptive_interval.dart';
import 'package:flutter_test/flutter_test.dart';

GpsUpdate _atSpeed(double speedMps) => GpsUpdate(
      memberId: 'me',
      latitude: 0,
      longitude: 0,
      headingDegrees: 0,
      speedMps: speedMps,
      timestamp: DateTime.utc(2026, 5, 13, 12, 0, 0),
    );

void main() {
  group('adaptiveGpsInterval', () {
    test('parked (0 km/h) returns 5 s', () {
      expect(adaptiveGpsInterval(_atSpeed(0)),
          const Duration(seconds: 5));
    });

    test('walking (3 km/h ≈ 0.83 m/s) still slow band -> 5 s', () {
      expect(adaptiveGpsInterval(_atSpeed(3 / 3.6)),
          const Duration(seconds: 5));
    });

    test('city speed (30 km/h ≈ 8.33 m/s) returns 1 s', () {
      expect(adaptiveGpsInterval(_atSpeed(30 / 3.6)),
          const Duration(seconds: 1));
    });

    test('highway (130 km/h) caps at 1 s', () {
      expect(adaptiveGpsInterval(_atSpeed(130 / 3.6)),
          const Duration(seconds: 1));
    });

    test('mid-range (15 km/h) interpolates between 5 s and 1 s', () {
      final d = adaptiveGpsInterval(_atSpeed(15 / 3.6));
      // 15 km/h is 40% of the way from 5 to 30 → 40% drop from 5 s to 1 s
      // expected ≈ 5000 - 0.4*4000 = 3400 ms
      expect(d.inMilliseconds, greaterThan(_fastInterval().inMilliseconds));
      expect(d.inMilliseconds, lessThan(_slowInterval().inMilliseconds));
      expect(d.inMilliseconds, closeTo(3400, 50));
    });

    test('monotonically non-increasing as speed grows', () {
      Duration prev = const Duration(seconds: 10);
      for (final kmh in [0, 5, 10, 15, 20, 25, 30, 60, 130]) {
        final d = adaptiveGpsInterval(_atSpeed(kmh / 3.6));
        expect(d.inMilliseconds, lessThanOrEqualTo(prev.inMilliseconds),
            reason: 'at $kmh km/h interval should not grow');
        prev = d;
      }
    });
  });
}

Duration _fastInterval() => const Duration(seconds: 1);
Duration _slowInterval() => const Duration(seconds: 5);
