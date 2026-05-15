import 'package:crew_link/core/geo/distance_engine.dart';
import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/application/geo_distance_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Convoy _convoy({double threshold = 500}) => Convoy(
      id: 'c1',
      name: 'Test',
      inviteCode: 'ABC',
      members: const [],
      proximityWarningMeters: threshold,
      createdAt: DateTime.utc(2026, 5, 14),
    );

GpsUpdate _pos(String id, {double lat = 0, double lon = 0}) => GpsUpdate(
      memberId: id,
      latitude: lat,
      longitude: lon,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: DateTime.utc(2026, 5, 14),
    );

ProviderContainer _container({
  Convoy? convoy,
  Map<String, GpsUpdate> positions = const {},
}) =>
    ProviderContainer(
      overrides: [
        currentConvoyProvider.overrideWith((ref) => convoy),
        livePositionsProvider.overrideWith((ref) => Stream.value(positions)),
      ],
    );

void main() {
  group('distanceEngineProvider', () {
    test('defaults to 500 m when no convoy is set', () {
      final c = _container();
      addTearDown(c.dispose);

      expect(c.read(distanceEngineProvider).thresholdMeters, 500.0);
    });

    test('uses convoy proximityWarningMeters as threshold', () {
      final c = _container(convoy: _convoy(threshold: 750));
      addTearDown(c.dispose);

      expect(c.read(distanceEngineProvider).thresholdMeters, 750.0);
    });

    test('rebuilds when convoy threshold changes', () {
      final c = ProviderContainer(
        overrides: [
          livePositionsProvider.overrideWith((ref) => const Stream.empty()),
        ],
      );
      addTearDown(c.dispose);

      c.read(currentConvoyProvider.notifier).state = _convoy(threshold: 300);
      expect(c.read(distanceEngineProvider).thresholdMeters, 300.0);

      c.read(currentConvoyProvider.notifier).state = _convoy(threshold: 800);
      expect(c.read(distanceEngineProvider).thresholdMeters, 800.0);
    });

    test('returns DistanceEngine instance', () {
      final c = _container(convoy: _convoy());
      addTearDown(c.dispose);

      expect(c.read(distanceEngineProvider), isA<DistanceEngine>());
    });
  });

  group('distancePairingsProvider', () {
    test('returns empty when no positions available', () {
      final c = _container(convoy: _convoy());
      addTearDown(c.dispose);

      // Stream hasn't emitted yet → valueOrNull == null → evaluate({}) → []
      expect(c.read(distancePairingsProvider), isEmpty);
    });

    test('returns empty when positions map is empty', () async {
      final c = _container(convoy: _convoy());
      addTearDown(c.dispose);

      await c.read(livePositionsProvider.future);
      expect(c.read(distancePairingsProvider), isEmpty);
    });

    test('returns empty when both members are within threshold', () async {
      // 0.004° lat ≈ 444 m < 500 m default threshold
      final c = _container(
        convoy: _convoy(),
        positions: {'a': _pos('a'), 'b': _pos('b', lat: 0.004)},
      );
      addTearDown(c.dispose);

      await c.read(livePositionsProvider.future);
      expect(c.read(distancePairingsProvider), isEmpty);
    });

    test('returns one pairing when members exceed threshold', () async {
      // 0.006° lat ≈ 667 m > 500 m
      final c = _container(
        convoy: _convoy(),
        positions: {'a': _pos('a'), 'b': _pos('b', lat: 0.006)},
      );
      addTearDown(c.dispose);

      await c.read(livePositionsProvider.future);
      final pairs = c.read(distancePairingsProvider);
      expect(pairs, hasLength(1));
      expect(pairs.single.distanceMeters, greaterThan(500));
    });

    test('respects custom convoy threshold — 667 m is within 1000 m', () async {
      // Same positions as above but threshold raised to 1000 m → no breach
      final c = _container(
        convoy: _convoy(threshold: 1000),
        positions: {'a': _pos('a'), 'b': _pos('b', lat: 0.006)},
      );
      addTearDown(c.dispose);

      await c.read(livePositionsProvider.future);
      expect(c.read(distancePairingsProvider), isEmpty);
    });

    test('strict threshold — 667 m breaches 600 m', () async {
      final c = _container(
        convoy: _convoy(threshold: 600),
        positions: {'a': _pos('a'), 'b': _pos('b', lat: 0.006)},
      );
      addTearDown(c.dispose);

      await c.read(livePositionsProvider.future);
      expect(c.read(distancePairingsProvider), hasLength(1));
    });

    test('detects all n*(n-1)/2 breached pairs for three members', () async {
      // Each pair is ~667 m+ apart
      final c = _container(
        convoy: _convoy(),
        positions: {
          'a': _pos('a'),
          'b': _pos('b', lat: 0.006),
          'c': _pos('c', lon: 0.008),
        },
      );
      addTearDown(c.dispose);

      await c.read(livePositionsProvider.future);
      // a↔b, a↔c, b↔c all > 500 m
      expect(c.read(distancePairingsProvider), hasLength(3));
    });

    test('each pairing appears exactly once', () async {
      final c = _container(
        convoy: _convoy(),
        positions: {
          'x': _pos('x'),
          'y': _pos('y', lat: 0.006),
          'z': _pos('z', lon: 0.008),
        },
      );
      addTearDown(c.dispose);

      await c.read(livePositionsProvider.future);
      final pairs = c.read(distancePairingsProvider);
      final keys =
          pairs.map((p) => '${p.memberAId}↔${p.memberBId}').toList();
      expect(keys.toSet().length, equals(keys.length));
    });
  });
}
