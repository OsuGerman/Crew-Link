import 'dart:async';

import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/data/location_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

GpsUpdate _u(double lat, DateTime ts) => GpsUpdate(
      memberId: 'me',
      latitude: lat,
      longitude: 13.40,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: ts,
    );

void main() {
  group('LocationPublisher offline-resilience', () {
    test('failed sink does not burn the throttle window', () async {
      final controller = StreamController<GpsUpdate>();
      addTearDown(controller.close);

      final emitted = <GpsUpdate>[];
      final errors = <Object>[];
      var failNext = true;
      var now = DateTime.utc(2026, 5, 13, 12, 0, 0);

      final publisher = LocationPublisher(
        source: controller.stream,
        sink: (update) {
          if (failNext) {
            throw StateError('socket reconnecting');
          }
          emitted.add(update);
        },
        minInterval: const Duration(seconds: 1),
        onError: (e, _) => errors.add(e),
        clock: () => now,
      )..start();
      addTearDown(publisher.dispose);

      // First emit — sink fails. _lastEmitAt must NOT advance.
      controller.add(_u(52.52, now));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(emitted, isEmpty);

      // Same wall-clock instant: socket recovers, next tick should
      // emit immediately (not be throttled out).
      failNext = false;
      controller.add(_u(52.53, now));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1),
          reason: 'a failed send must not block the next live position');
      expect(emitted.single.latitude, 52.53);
    });
  });
}
