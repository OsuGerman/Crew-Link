import 'dart:async';

import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/data/location_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

GpsUpdate _u(double speedMps, DateTime ts) => GpsUpdate(
      memberId: 'me',
      latitude: 0,
      longitude: 0,
      headingDegrees: 0,
      speedMps: speedMps,
      timestamp: ts,
    );

void main() {
  group('LocationPublisher with intervalStrategy', () {
    test('strategy result overrides the constant minInterval', () async {
      final controller = StreamController<GpsUpdate>();
      addTearDown(controller.close);
      final emitted = <GpsUpdate>[];
      var now = DateTime.utc(2026, 5, 13, 12, 0, 0);

      final publisher = LocationPublisher(
        source: controller.stream,
        sink: emitted.add,
        minInterval: const Duration(milliseconds: 100),
        // Strategy says: every update needs 1 s gap regardless of speed.
        intervalStrategy: (_) => const Duration(seconds: 1),
        clock: () => now,
      )..start();
      addTearDown(publisher.dispose);

      controller.add(_u(0, now));
      await Future<void>.delayed(Duration.zero);

      // 200 ms later — would have passed the 100 ms minInterval but
      // strategy says 1 s, so this must be throttled out.
      now = now.add(const Duration(milliseconds: 200));
      controller.add(_u(0, now));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1),
          reason: 'strategy 1 s must win over constant 100 ms');
    });

    test('per-update interval depends on the update value', () async {
      final controller = StreamController<GpsUpdate>();
      addTearDown(controller.close);
      final emitted = <GpsUpdate>[];
      var now = DateTime.utc(2026, 5, 13, 12, 0, 0);

      // Strategy: speed < 1 m/s -> 5 s, else 100 ms.
      final publisher = LocationPublisher(
        source: controller.stream,
        sink: emitted.add,
        intervalStrategy: (u) => u.speedMps < 1
            ? const Duration(seconds: 5)
            : const Duration(milliseconds: 100),
        clock: () => now,
      )..start();
      addTearDown(publisher.dispose);

      controller.add(_u(0, now)); // parked
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));

      // 200 ms later, still parked (speed=0). Strategy says 5 s — must
      // throttle out even though 200 ms have passed.
      now = now.add(const Duration(milliseconds: 200));
      controller.add(_u(0, now));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));

      // 200 ms later, suddenly moving. Strategy says 100 ms and 400 ms
      // total have passed since the previous emit — must emit.
      now = now.add(const Duration(milliseconds: 200));
      controller.add(_u(10, now));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(2));
    });
  });
}
