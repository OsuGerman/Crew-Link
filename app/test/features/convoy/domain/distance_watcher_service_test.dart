import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/domain/distance_watcher_service.dart';
import 'package:crew_link/features/convoy/domain/proximity_warning.dart';
import 'package:flutter_test/flutter_test.dart';

GpsUpdate _u(
  String memberId,
  double lat,
  double lon, {
  DateTime? timestamp,
}) =>
    GpsUpdate(
      memberId: memberId,
      latitude: lat,
      longitude: lon,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: timestamp ?? DateTime.utc(2026, 5, 14, 10),
    );

void main() {
  group('DistanceWatcherService', () {
    test('no warning when peer is within 500 m', () async {
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 14, 10),
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      svc.ingest(_u('me', 52.5200, 13.4050));
      // ~68 m — well within 500 m
      svc.ingest(_u('peer', 52.5200, 13.4060));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);
    });

    test('emits warning when peer exceeds 500 m', () async {
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 14, 10),
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      svc.ingest(_u('me', 52.5200, 13.4050));
      // ~4.5 km — clearly exceeds 500 m
      svc.ingest(_u('peer', 52.5600, 13.4050));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      expect(emitted.single.otherMemberId, 'peer');
      expect(emitted.single.distanceMeters, greaterThan(500));
      expect(emitted.single.thresholdMeters, 500);
    });

    test('warning carries distanceMeters and triggeredAt from clock', () async {
      final pinnedNow = DateTime.utc(2026, 5, 14, 10);
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => pinnedNow,
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      svc.ingest(_u('me', 52.5200, 13.4050));
      svc.ingest(_u('peer', 52.5600, 13.4050));
      await Future<void>.delayed(Duration.zero);

      expect(emitted.single.triggeredAt, pinnedNow);
      expect(emitted.single.distanceMeters, greaterThan(500));
    });

    test('hysteresis: no re-fire while peer is still breached', () async {
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 14, 10),
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      svc.ingest(_u('me', 52.5200, 13.4050));
      svc.ingest(_u('peer', 52.5600, 13.4050)); // breached, ~4.5 km
      svc.ingest(_u('peer', 52.5550, 13.4050)); // still > 500 m but closer
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
    });

    test('re-arms after peer returns within 80 % of threshold (400 m)',
        () async {
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 14, 10),
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      svc.ingest(_u('me', 52.5200, 13.4050));
      svc.ingest(_u('peer', 52.5600, 13.4050)); // breach → warning #1
      // peer returns very close (< 400 m) → re-arms
      svc.ingest(_u('peer', 52.5200, 13.4060)); // ~68 m → clears breached set
      svc.ingest(_u('peer', 52.5600, 13.4050)); // breach again → warning #2
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(2));
    });

    test('no warning without self position yet', () async {
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 14, 10),
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      svc.ingest(_u('peer', 52.5600, 13.4050));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);
    });

    test('re-evaluates all peers when self position updates', () async {
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 14, 10),
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      // peer arrives but no self yet → no warning
      svc.ingest(_u('peer', 52.5600, 13.4050));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);

      // self appears far from peer → breach fires
      svc.ingest(_u('me', 52.5200, 13.4050));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
      expect(emitted.single.otherMemberId, 'peer');
    });

    test('suppresses warning when peer position is stale', () async {
      var now = DateTime.utc(2026, 5, 14, 10);
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        maxPositionAge: const Duration(seconds: 30),
        clock: () => now,
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      // peer has a timestamp far in the past
      svc.ingest(_u('peer', 52.5600, 13.4050,
          timestamp: now.subtract(const Duration(minutes: 5))));
      svc.ingest(_u('me', 52.5200, 13.4050));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty, reason: 'stale peer must not trigger breach');
    });

    test('suppresses warning when self position is stale', () async {
      var now = DateTime.utc(2026, 5, 14, 10);
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        maxPositionAge: const Duration(seconds: 30),
        clock: () => now,
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      // self arrives, then clock advances
      svc.ingest(_u('me', 52.5200, 13.4050));
      now = now.add(const Duration(minutes: 5));
      svc.ingest(_u('peer', 52.5600, 13.4050));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty, reason: 'stale self must not trigger breach');
    });

    test('fires independently for multiple breached peers', () async {
      final svc = DistanceWatcherService(
        selfMemberId: 'me',
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 14, 10),
      );
      addTearDown(svc.dispose);
      final emitted = <ProximityWarning>[];
      final sub = svc.warnings.listen(emitted.add);
      addTearDown(sub.cancel);

      svc.ingest(_u('me', 52.5200, 13.4050));
      svc.ingest(_u('peer-a', 52.5600, 13.4050));
      svc.ingest(_u('peer-b', 52.5700, 13.4050));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(2));
      expect(
        emitted.map((w) => w.otherMemberId),
        containsAll(['peer-a', 'peer-b']),
      );
    });
  });
}
