import 'dart:async';

import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/data/location_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

GpsUpdate _u(double lat, double lon, DateTime ts) => GpsUpdate(
      memberId: 'me',
      latitude: lat,
      longitude: lon,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: ts,
    );

void main() {
  group('LocationPublisher', () {
    test('forwards the first update immediately', () async {
      final controller = StreamController<GpsUpdate>();
      addTearDown(controller.close);
      final emitted = <GpsUpdate>[];
      var now = DateTime.utc(2026, 5, 13, 12, 0, 0);
      final publisher = LocationPublisher(
        source: controller.stream,
        sink: emitted.add,
        minInterval: const Duration(seconds: 1),
        clock: () => now,
      )..start();
      addTearDown(publisher.dispose);

      controller.add(_u(52.52, 13.40, now));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      expect(emitted.single.latitude, 52.52);
    });

    test('throttles bursts within minInterval window', () async {
      final controller = StreamController<GpsUpdate>();
      addTearDown(controller.close);
      final emitted = <GpsUpdate>[];
      var now = DateTime.utc(2026, 5, 13, 12, 0, 0);
      final publisher = LocationPublisher(
        source: controller.stream,
        sink: emitted.add,
        minInterval: const Duration(seconds: 1),
        clock: () => now,
      )..start();
      addTearDown(publisher.dispose);

      controller.add(_u(52.52, 13.40, now));
      await Future<void>.delayed(Duration.zero);

      // 200ms later — must be throttled out.
      now = now.add(const Duration(milliseconds: 200));
      controller.add(_u(52.53, 13.40, now));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1),
          reason: 'second update inside throttle window must be skipped');
    });

    test('flushes the latest skipped update after the throttle window',
        () async {
      final controller = StreamController<GpsUpdate>();
      addTearDown(controller.close);
      final emitted = <GpsUpdate>[];
      var now = DateTime.utc(2026, 5, 13, 12, 0, 0);
      final publisher = LocationPublisher(
        source: controller.stream,
        sink: emitted.add,
        minInterval: const Duration(milliseconds: 100),
        clock: () => now,
      )..start();
      addTearDown(publisher.dispose);

      controller.add(_u(52.52, 13.40, now));
      await Future<void>.delayed(Duration.zero);

      // two rapid updates inside window — only the most recent must flush
      now = now.add(const Duration(milliseconds: 20));
      controller.add(_u(52.521, 13.40, now));
      now = now.add(const Duration(milliseconds: 20));
      controller.add(_u(52.522, 13.40, now));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));

      // Advance wall clock past the throttle window before timer fires.
      now = now.add(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(emitted, hasLength(2));
      expect(emitted.last.latitude, 52.522,
          reason: 'latest skipped update is the one flushed');
    });

    test('swallows source errors via onError', () async {
      final controller = StreamController<GpsUpdate>();
      addTearDown(controller.close);
      final emitted = <GpsUpdate>[];
      final errors = <Object>[];
      final publisher = LocationPublisher(
        source: controller.stream,
        sink: emitted.add,
        onError: (e, _) => errors.add(e),
      )..start();
      addTearDown(publisher.dispose);

      controller.addError(StateError('gps offline'));
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(publisher.isRunning, isTrue,
          reason: 'transient GPS error must not tear down the publisher');
    });

    test('stop cancels pending flush', () async {
      final controller = StreamController<GpsUpdate>();
      addTearDown(controller.close);
      final emitted = <GpsUpdate>[];
      var now = DateTime.utc(2026, 5, 13, 12, 0, 0);
      final publisher = LocationPublisher(
        source: controller.stream,
        sink: emitted.add,
        minInterval: const Duration(milliseconds: 100),
        clock: () => now,
      )..start();
      addTearDown(publisher.dispose);

      controller.add(_u(52.52, 13.40, now));
      await Future<void>.delayed(Duration.zero);

      now = now.add(const Duration(milliseconds: 20));
      controller.add(_u(52.53, 13.40, now)); // queued for flush
      await Future<void>.delayed(Duration.zero);

      await publisher.stop();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(emitted, hasLength(1),
          reason: 'pending flush must not fire after stop()');
    });
  });
}
