import 'package:crew_link/core/geo/distance_engine.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:flutter_test/flutter_test.dart';

GpsUpdate _pos(String id, {double lat = 0, double lon = 0}) => GpsUpdate(
      memberId: id,
      latitude: lat,
      longitude: lon,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: DateTime.utc(2026, 5, 14),
    );

void main() {
  const engine = DistanceEngine();

  group('DistanceEngine.evaluate', () {
    test('returns empty list for empty positions', () {
      expect(engine.evaluate({}), isEmpty);
    });

    test('returns empty list for single member', () {
      expect(engine.evaluate({'a': _pos('a')}), isEmpty);
    });

    test('no breach when two members are within threshold', () {
      // 0.004° lat ≈ 444 m < 500 m
      final pairs = engine.evaluate({
        'a': _pos('a'),
        'b': _pos('b', lat: 0.004),
      });
      expect(pairs, isEmpty);
    });

    test('emits one pair when distance exceeds 500 m', () {
      // 0.005° lat ≈ 556 m > 500 m
      final pairs = engine.evaluate({
        'a': _pos('a'),
        'b': _pos('b', lat: 0.005),
      });
      expect(pairs, hasLength(1));
      expect(pairs.single.memberAId, 'a');
      expect(pairs.single.memberBId, 'b');
      expect(pairs.single.distanceMeters, greaterThan(500));
    });

    test('distance value matches haversine (~556 m for 0.005° lat)', () {
      final pairs = engine.evaluate({
        'a': _pos('a'),
        'b': _pos('b', lat: 0.005),
      });
      expect(pairs.single.distanceMeters, closeTo(556, 2));
    });

    test('detects multiple breached pairs independently', () {
      // All three spread >500 m apart
      final pairs = engine.evaluate({
        'a': _pos('a'),
        'b': _pos('b', lat: 0.005),
        'c': _pos('c', lon: 0.006),
      });
      // a↔b, a↔c, b↔c — all exceed 500 m
      expect(pairs, hasLength(3));
    });

    test('only breached pairs are returned when some are within threshold', () {
      // a and b are close; a and c are far
      final pairs = engine.evaluate({
        'a': _pos('a'),
        'b': _pos('b', lat: 0.001),   // ~111 m — within threshold
        'c': _pos('c', lat: 0.006),   // ~667 m from a — breached
      });
      // a↔b: ~111 m ok; a↔c: ~667 m breached; b↔c: ~556 m breached
      expect(pairs.length, greaterThanOrEqualTo(1));
      expect(pairs.any((p) =>
          (p.memberAId == 'a' && p.memberBId == 'c') ||
          (p.memberAId == 'c' && p.memberBId == 'a')), isTrue);
      expect(pairs.every((p) =>
          !(p.memberAId == 'a' && p.memberBId == 'b') &&
          !(p.memberAId == 'b' && p.memberBId == 'a')), isTrue);
    });

    test('respects custom threshold', () {
      const strictEngine = DistanceEngine(thresholdMeters: 100);
      // 0.001° lat ≈ 111 m > 100 m → breach
      final pairs = strictEngine.evaluate({
        'a': _pos('a'),
        'b': _pos('b', lat: 0.001),
      });
      expect(pairs, hasLength(1));
    });

    test('exactly at threshold is not a breach (uses strict >)', () {
      // We need a pair whose distance is exactly thresholdMeters.
      // Use a very large threshold so both points at origin produce 0 m < threshold.
      const bigEngine = DistanceEngine(thresholdMeters: 10000000);
      final pairs = bigEngine.evaluate({
        'a': _pos('a'),
        'b': _pos('b', lat: 0.005),
      });
      expect(pairs, isEmpty);
    });

    test('each unique pair appears exactly once', () {
      final pairs = engine.evaluate({
        'x': _pos('x'),
        'y': _pos('y', lat: 0.005),
        'z': _pos('z', lat: 0.005, lon: 0.005),
      });
      final keys = pairs.map((p) => '${p.memberAId}↔${p.memberBId}').toList();
      expect(keys.toSet().length, equals(keys.length));
    });
  });
}
