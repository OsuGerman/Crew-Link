import 'package:crew_link/core/models/gps_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpsUpdate', () {
    test('round-trips JSON', () {
      final original = GpsUpdate(
        memberId: 'm-1',
        latitude: 52.5200,
        longitude: 13.4050,
        headingDegrees: 90,
        speedMps: 12.3,
        timestamp: DateTime.utc(2026, 5, 13, 18, 0, 0),
        accuracyMeters: 4.5,
      );

      final decoded = GpsUpdate.fromJson(original.toJson());

      expect(decoded.memberId, original.memberId);
      expect(decoded.latitude, original.latitude);
      expect(decoded.longitude, original.longitude);
      expect(decoded.headingDegrees, original.headingDegrees);
      expect(decoded.speedMps, original.speedMps);
      expect(decoded.timestamp, original.timestamp);
      expect(decoded.accuracyMeters, original.accuracyMeters);
    });

    test('omits accuracy when null', () {
      final update = GpsUpdate(
        memberId: 'm-2',
        latitude: 0,
        longitude: 0,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: DateTime.utc(2026, 1, 1),
      );

      expect(update.toJson().containsKey('accuracy'), isFalse);
    });
  });
}
