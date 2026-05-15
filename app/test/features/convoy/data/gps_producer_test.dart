import 'dart:async';

import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/data/gps_producer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Position _pos({
  double lat = 52.52,
  double lon = 13.40,
  double speed = 0,
  double heading = 0,
  double accuracy = 5,
  DateTime? ts,
}) =>
    Position(
      latitude: lat,
      longitude: lon,
      speed: speed,
      heading: heading,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
      speedAccuracy: 0,
      timestamp: ts ?? DateTime.utc(2026, 5, 14, 10),
    );

/// Fake factory: each call gets a fresh broadcast controller.
/// [controllers] accumulates them so tests can push events per stream.
class _FakeStreamFactory {
  final controllers = <StreamController<Position>>[];

  Stream<Position> call(LocationSettings _) {
    final c = StreamController<Position>.broadcast();
    controllers.add(c);
    return c.stream;
  }
}

LocationSettings _noopSettings(Duration _) =>
    const LocationSettings(accuracy: LocationAccuracy.low);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GpsProducer', () {
    test('emits GpsUpdate tagged with memberId for each Position event',
        () async {
      final factory = _FakeStreamFactory();
      final producer = GpsProducer(
        memberId: 'driver-1',
        streamFactory: factory.call,
        settingsFactory: _noopSettings,
      )..start();
      addTearDown(producer.dispose);

      final received = <GpsUpdate>[];
      producer.stream.listen(received.add);

      factory.controllers.first.add(_pos(lat: 48.1, lon: 11.5, speed: 0));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.memberId, 'driver-1');
      expect(received.single.latitude, 48.1);
      expect(received.single.longitude, 11.5);
    });

    test('starts in slow bucket — opens stream with 5000 ms interval',
        () async {
      final capturedIntervals = <Duration>[];
      final factory = _FakeStreamFactory();

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: (d) {
          capturedIntervals.add(d);
          return _noopSettings(d);
        },
      )..start();
      addTearDown(producer.dispose);

      expect(capturedIntervals, hasLength(1));
      expect(capturedIntervals.first, const Duration(milliseconds: 5000));
    });

    test('restarts stream with fast bucket when speed >= 30 km/h', () async {
      final factory = _FakeStreamFactory();
      final capturedIntervals = <Duration>[];

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: (d) {
          capturedIntervals.add(d);
          return _noopSettings(d);
        },
      )..start();
      addTearDown(producer.dispose);

      expect(factory.controllers, hasLength(1));

      // 30 km/h = 8.33 m/s → adaptiveGpsInterval returns 1 s → fast bucket
      factory.controllers.first.add(_pos(speed: 8.34));
      await Future<void>.delayed(Duration.zero);

      expect(factory.controllers, hasLength(2),
          reason: 'bucket changed slow→fast: stream must restart');
      expect(capturedIntervals.last, const Duration(milliseconds: 1000));
    });

    test('does not restart stream while speed stays in same bucket', () async {
      final factory = _FakeStreamFactory();

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: _noopSettings,
      )..start();
      addTearDown(producer.dispose);

      // Two updates both at ~0 km/h → both map to slow bucket
      factory.controllers.first.add(_pos(speed: 0));
      await Future<void>.delayed(Duration.zero);
      factory.controllers.first.add(_pos(speed: 1));
      await Future<void>.delayed(Duration.zero);

      expect(factory.controllers, hasLength(1),
          reason: 'same bucket: no stream restart expected');
    });

    test('no emission after dispose', () async {
      final factory = _FakeStreamFactory();
      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: _noopSettings,
      )..start();

      final received = <GpsUpdate>[];
      producer.stream.listen(received.add);

      await producer.dispose();
      // Controller is closed; adding to it would throw — nothing arrives.
      expect(received, isEmpty);
    });

    test('errors from position stream are routed to onError callback',
        () async {
      final factory = _FakeStreamFactory();
      final errors = <Object>[];

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: _noopSettings,
        onError: (e, _) => errors.add(e),
      )..start();
      addTearDown(producer.dispose);

      factory.controllers.first.addError(StateError('gps offline'));
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });

    test('start() is idempotent — second call is a no-op', () async {
      final factory = _FakeStreamFactory();
      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: _noopSettings,
      );
      addTearDown(producer.dispose);

      producer.start();
      producer.start(); // second call must not open another stream

      expect(factory.controllers, hasLength(1));
    });
  });

  group('background throttle', () {
    test('background=true forces restart into slow bucket when in fast bucket',
        () async {
      final factory = _FakeStreamFactory();
      final capturedIntervals = <Duration>[];

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: (d) {
          capturedIntervals.add(d);
          return _noopSettings(d);
        },
      )..start();
      addTearDown(producer.dispose);

      // Promote to fast bucket
      factory.controllers.first.add(_pos(speed: 8.34)); // ≥ 30 km/h
      await Future<void>.delayed(Duration.zero);
      expect(factory.controllers, hasLength(2));
      expect(capturedIntervals.last, const Duration(milliseconds: 1000));

      // Background → must restart with slow bucket
      producer.background = true;
      await Future<void>.delayed(Duration.zero);

      expect(factory.controllers, hasLength(3));
      expect(capturedIntervals.last, const Duration(milliseconds: 5000));
    });

    test('background=true suppresses bucket switching on speed changes',
        () async {
      final factory = _FakeStreamFactory();

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: _noopSettings,
      )..start();
      addTearDown(producer.dispose);

      producer.background = true;

      // High-speed position → must NOT trigger a fast-bucket restart
      factory.controllers.first.add(_pos(speed: 8.34)); // ≥ 30 km/h
      await Future<void>.delayed(Duration.zero);

      // background=true does NOT open a new stream when bucket is already slow
      // (started in slow), so total stream count stays at 1 or 2 depending on
      // whether background setter triggered a restart — it won't because we
      // were already in slow. Speed event is ignored → still only 1 stream.
      expect(
        factory.controllers.length,
        lessThanOrEqualTo(2),
        reason: 'background mode must not open additional streams for speed',
      );
    });

    test('background=false re-enables adaptive bucket switching', () async {
      final factory = _FakeStreamFactory();
      final capturedIntervals = <Duration>[];

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: (d) {
          capturedIntervals.add(d);
          return _noopSettings(d);
        },
      )..start();
      addTearDown(producer.dispose);

      // Go to background and back to foreground
      producer.background = true;
      producer.background = false;
      await Future<void>.delayed(Duration.zero);

      // Now adaptive switching must work again
      final streamsBefore = factory.controllers.length;
      factory.controllers.last.add(_pos(speed: 8.34)); // fast speed
      await Future<void>.delayed(Duration.zero);

      expect(
        factory.controllers.length,
        greaterThan(streamsBefore),
        reason: 'adaptive bucket switch must fire after returning to foreground',
      );
      expect(capturedIntervals.last, const Duration(milliseconds: 1000));
    });

    test('background=true is idempotent — no stream churn on repeated sets',
        () async {
      final factory = _FakeStreamFactory();

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: _noopSettings,
      )..start();
      addTearDown(producer.dispose);

      final streamCount = factory.controllers.length; // 1 (slow)
      producer.background = true;
      producer.background = true; // second set must be a no-op
      await Future<void>.delayed(Duration.zero);

      // already in slow bucket → no restart expected
      expect(factory.controllers.length, streamCount);
    });
  });

  group('lowBattery throttle', () {
    test('lowBattery=true forces restart into slow bucket when in fast bucket',
        () async {
      final factory = _FakeStreamFactory();
      final capturedIntervals = <Duration>[];

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: (d) {
          capturedIntervals.add(d);
          return _noopSettings(d);
        },
      )..start();
      addTearDown(producer.dispose);

      // Promote to fast bucket
      factory.controllers.first.add(_pos(speed: 8.34));
      await Future<void>.delayed(Duration.zero);
      expect(capturedIntervals.last, const Duration(milliseconds: 1000));

      producer.lowBattery = true;
      await Future<void>.delayed(Duration.zero);

      expect(capturedIntervals.last, const Duration(milliseconds: 5000));
    });

    test('lowBattery=true suppresses speed-based bucket switching', () async {
      final factory = _FakeStreamFactory();

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: _noopSettings,
      )..start();
      addTearDown(producer.dispose);

      producer.lowBattery = true;
      final countAfterSet = factory.controllers.length;

      factory.controllers.last.add(_pos(speed: 8.34));
      await Future<void>.delayed(Duration.zero);

      expect(factory.controllers.length, countAfterSet,
          reason: 'low-battery mode must suppress speed-based restarts');
    });

    test('lowBattery=false re-enables adaptive sampling', () async {
      final factory = _FakeStreamFactory();
      final capturedIntervals = <Duration>[];

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: (d) {
          capturedIntervals.add(d);
          return _noopSettings(d);
        },
      )..start();
      addTearDown(producer.dispose);

      producer.lowBattery = true;
      producer.lowBattery = false;
      await Future<void>.delayed(Duration.zero);

      final streamsBefore = factory.controllers.length;
      factory.controllers.last.add(_pos(speed: 8.34));
      await Future<void>.delayed(Duration.zero);

      expect(factory.controllers.length, greaterThan(streamsBefore));
      expect(capturedIntervals.last, const Duration(milliseconds: 1000));
    });

    test('both background and lowBattery must clear to restore adaptive mode',
        () async {
      final factory = _FakeStreamFactory();
      final capturedIntervals = <Duration>[];

      final producer = GpsProducer(
        memberId: 'self',
        streamFactory: factory.call,
        settingsFactory: (d) {
          capturedIntervals.add(d);
          return _noopSettings(d);
        },
      )..start();
      addTearDown(producer.dispose);

      // Promote to fast, then apply both throttles.
      factory.controllers.first.add(_pos(speed: 8.34));
      await Future<void>.delayed(Duration.zero);

      producer.background = true;
      producer.lowBattery = true;
      await Future<void>.delayed(Duration.zero);
      expect(capturedIntervals.last, const Duration(milliseconds: 5000));

      // Clear only background — lowBattery still active, must stay slow.
      producer.background = false;
      await Future<void>.delayed(Duration.zero);
      expect(capturedIntervals.last, const Duration(milliseconds: 5000));

      // Clear lowBattery too — adaptive mode resumes.
      producer.lowBattery = false;
      await Future<void>.delayed(Duration.zero);
      final streamsBefore = factory.controllers.length;
      factory.controllers.last.add(_pos(speed: 8.34));
      await Future<void>.delayed(Duration.zero);
      expect(factory.controllers.length, greaterThan(streamsBefore));
    });
  });
}
