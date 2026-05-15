import 'dart:async';

import 'package:crew_link/features/convoy/data/platform_location_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position _pos({
  double lat = 52.52,
  double lon = 13.40,
  double heading = 90,
  double speed = 12,
  double accuracy = 5,
  DateTime? ts,
}) {
  return Position(
    longitude: lon,
    latitude: lat,
    timestamp: ts ?? DateTime.utc(2026, 5, 13, 12),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: heading,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}

void main() {
  group('PlatformLocationAdapter', () {
    test('maps Position events to GpsUpdate tagged with memberId', () async {
      final controller = StreamController<Position>();
      addTearDown(controller.close);

      final adapter = PlatformLocationAdapter(
        memberId: 'self-123',
        factory: (_) => controller.stream,
      );

      final out = adapter.stream();
      final received = <Object>[];
      final sub = out.listen(received.add);
      addTearDown(sub.cancel);

      controller.add(_pos(lat: 1, lon: 2, heading: 45, speed: 10, accuracy: 7));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      final update = received.single as dynamic;
      expect(update.memberId, 'self-123');
      expect(update.latitude, 1);
      expect(update.longitude, 2);
      expect(update.headingDegrees, 45);
      expect(update.speedMps, 10);
      expect(update.accuracyMeters, 7);
    });

    test('propagates upstream errors to the consumer', () async {
      final controller = StreamController<Position>();
      addTearDown(controller.close);

      final adapter = PlatformLocationAdapter(
        memberId: 'self',
        factory: (_) => controller.stream,
      );

      final errors = <Object>[];
      final sub = adapter.stream().listen(
            (_) {},
            onError: errors.add,
            cancelOnError: false,
          );
      addTearDown(sub.cancel);

      controller.addError(StateError('gps offline'));
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });

    test('passes provided LocationSettings to the factory', () {
      LocationSettings? captured;
      final adapter = PlatformLocationAdapter(
        memberId: 'self',
        settings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
        factory: (s) {
          captured = s;
          return const Stream<Position>.empty();
        },
      );
      adapter.stream().listen((_) {});
      expect(captured, isNotNull);
      expect(captured!.accuracy, LocationAccuracy.high);
      expect(captured!.distanceFilter, 25);
    });
  });
}
