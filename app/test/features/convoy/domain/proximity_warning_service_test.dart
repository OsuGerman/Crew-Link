import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/domain/proximity_warning.dart';
import 'package:crew_link/features/convoy/domain/proximity_warning_service.dart';
import 'package:flutter_test/flutter_test.dart';

GpsUpdate _u(String memberId, double lat, double lon) => GpsUpdate(
      memberId: memberId,
      latitude: lat,
      longitude: lon,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: DateTime.utc(2026, 5, 13, 12, 0, 0),
    );

void main() {
  group('ProximityWarningService', () {
    test('emits warning when other member is within threshold', () async {
      final service = ProximityWarningService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(service.dispose);

      final emitted = <ProximityWarning>[];
      final sub = service.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      service.ingest(_u('me', 52.5200, 13.4050));
      // ~78m to the east of self (0.001° lon at lat 52 is ~68m)
      service.ingest(_u('peer', 52.5200, 13.4060));

      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
      expect(emitted.single.otherMemberId, 'peer');
      expect(emitted.single.distanceMeters, lessThan(500));
    });

    test('does not emit when other member is beyond threshold', () async {
      final service = ProximityWarningService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(service.dispose);

      final emitted = <ProximityWarning>[];
      final sub = service.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      service.ingest(_u('me', 52.5200, 13.4050));
      // ~5km away
      service.ingest(_u('peer', 52.5650, 13.4050));

      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);
    });

    test('hysteresis: no duplicate warning while still inside release band',
        () async {
      final service = ProximityWarningService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(service.dispose);

      final emitted = <ProximityWarning>[];
      final sub = service.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      service.ingest(_u('me', 52.5200, 13.4050));
      service.ingest(_u('peer', 52.5200, 13.4060)); // ~78m, triggers
      service.ingest(_u('peer', 52.5200, 13.4062)); // ~93m, still close

      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
    });

    test('re-arms after peer leaves release band (>1.2*threshold)', () async {
      final service = ProximityWarningService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(service.dispose);

      final emitted = <ProximityWarning>[];
      final sub = service.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      service.ingest(_u('me', 52.5200, 13.4050));
      service.ingest(_u('peer', 52.5200, 13.4060)); // inside threshold
      service.ingest(_u('peer', 52.5300, 13.4050)); // ~1.1km away — releases
      service.ingest(_u('peer', 52.5200, 13.4060)); // back inside — re-fires

      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(2));
    });

    test('suppresses warning when peer position is stale', () async {
      var now = DateTime.utc(2026, 5, 13, 12, 0, 0);
      final service = ProximityWarningService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        maxPositionAge: const Duration(seconds: 30),
        clock: () => now,
      );
      addTearDown(service.dispose);

      final emitted = <ProximityWarning>[];
      final sub = service.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      // peer at t=0
      service.ingest(GpsUpdate(
        memberId: 'peer',
        latitude: 52.5200,
        longitude: 13.4060,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: now,
      ));
      // advance clock past maxPositionAge before self appears
      now = now.add(const Duration(minutes: 2));
      service.ingest(GpsUpdate(
        memberId: 'me',
        latitude: 52.5200,
        longitude: 13.4050,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: now,
      ));

      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty,
          reason: 'stale peer must not trigger a warning');
    });

    test('fires once peer refreshes after being stale', () async {
      var now = DateTime.utc(2026, 5, 13, 12, 0, 0);
      final service = ProximityWarningService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        maxPositionAge: const Duration(seconds: 30),
        clock: () => now,
      );
      addTearDown(service.dispose);

      final emitted = <ProximityWarning>[];
      final sub = service.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      // self present, peer arrives stale (timestamp far in the past)
      service.ingest(GpsUpdate(
        memberId: 'me',
        latitude: 52.5200,
        longitude: 13.4050,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: now,
      ));
      service.ingest(GpsUpdate(
        memberId: 'peer',
        latitude: 52.5200,
        longitude: 13.4060,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: now.subtract(const Duration(minutes: 5)),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);

      // peer refreshes with a current timestamp -> warning fires.
      service.ingest(GpsUpdate(
        memberId: 'peer',
        latitude: 52.5200,
        longitude: 13.4060,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: now,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
    });

    test('warning.triggeredAt comes from the injected clock', () async {
      final pinnedNow = DateTime.utc(2026, 5, 13, 12, 0, 0);
      final service = ProximityWarningService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => pinnedNow,
      );
      addTearDown(service.dispose);

      final emitted = <ProximityWarning>[];
      final sub = service.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      service.ingest(_u('me', 52.5200, 13.4050));
      service.ingest(_u('peer', 52.5200, 13.4060));

      await Future<void>.delayed(Duration.zero);
      expect(emitted.single.triggeredAt, pinnedNow);
    });

    test('re-evaluates all peers when self position updates', () async {
      final service = ProximityWarningService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(service.dispose);

      final emitted = <ProximityWarning>[];
      final sub = service.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      // peer ingested first — no self yet
      service.ingest(_u('peer', 52.5200, 13.4060));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);

      // self appears nearby — peer should now trigger warning
      service.ingest(_u('me', 52.5200, 13.4050));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
      expect(emitted.single.otherMemberId, 'peer');
    });
  });
}
