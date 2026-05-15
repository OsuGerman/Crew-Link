import 'dart:async';

import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/domain/convoy_session.dart';
import 'package:crew_link/features/convoy/domain/proximity_warning.dart';
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
  group('ConvoySession', () {
    test('relays incoming GPS updates to listeners', () async {
      final transport = StreamController<GpsUpdate>();
      final session = ConvoySession(
        selfMemberId: 'me',
        incoming: transport.stream,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(() async {
        await session.dispose();
        await transport.close();
      });

      final relayed = <GpsUpdate>[];
      final sub = session.gpsUpdates.listen(relayed.add);
      addTearDown(sub.cancel);

      session.start();
      transport.add(_u('peer', 52.5200, 13.4060));
      transport.add(_u('me', 52.5200, 13.4050));

      await Future<void>.delayed(Duration.zero);
      expect(relayed.map((u) => u.memberId).toList(), ['peer', 'me']);
    });

    test('emits proximity warning when peer is within threshold', () async {
      final transport = StreamController<GpsUpdate>();
      final session = ConvoySession(
        selfMemberId: 'me',
        incoming: transport.stream,
        thresholdMeters: 500,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(() async {
        await session.dispose();
        await transport.close();
      });

      final warnings = <ProximityWarning>[];
      final sub = session.warnings.listen(warnings.add);
      addTearDown(sub.cancel);

      session.start();
      transport.add(_u('me', 52.5200, 13.4050));
      transport.add(_u('peer', 52.5200, 13.4060)); // ~78m

      await Future<void>.delayed(Duration.zero);
      expect(warnings, hasLength(1));
      expect(warnings.single.otherMemberId, 'peer');
    });

    test('start() is idempotent', () async {
      final transport = StreamController<GpsUpdate>.broadcast();
      final session = ConvoySession(
        selfMemberId: 'me',
        incoming: transport.stream,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(() async {
        await session.dispose();
        await transport.close();
      });

      final relayed = <GpsUpdate>[];
      final sub = session.gpsUpdates.listen(relayed.add);
      addTearDown(sub.cancel);

      session.start();
      session.start(); // second call must not double-subscribe
      transport.add(_u('peer', 52.5200, 13.4060));

      await Future<void>.delayed(Duration.zero);
      expect(relayed, hasLength(1));
    });

    test('dispose cancels transport subscription and closes streams',
        () async {
      final transport = StreamController<GpsUpdate>();
      final session = ConvoySession(
        selfMemberId: 'me',
        incoming: transport.stream,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );

      session.start();
      await session.dispose();

      // Transport should now have no listeners.
      expect(transport.hasListener, isFalse);

      await transport.close();
    });

    test('positions stream emits latest snapshot keyed by memberId',
        () async {
      final transport = StreamController<GpsUpdate>();
      final session = ConvoySession(
        selfMemberId: 'me',
        incoming: transport.stream,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(() async {
        await session.dispose();
        await transport.close();
      });

      final snapshots = <Map<String, GpsUpdate>>[];
      final sub = session.positions.listen(snapshots.add);
      addTearDown(sub.cancel);

      session.start();
      transport.add(_u('peer-a', 52.5200, 13.4060));
      transport.add(_u('peer-b', 52.5210, 13.4070));
      transport.add(_u('peer-a', 52.5300, 13.4080));

      await Future<void>.delayed(Duration.zero);

      expect(snapshots, hasLength(3));
      expect(snapshots.last.keys, containsAll(['peer-a', 'peer-b']));
      expect(snapshots.last['peer-a']!.latitude, 52.5300);
      expect(session.latestPositions['peer-b']!.longitude, 13.4070);
    });

    test('older timestamps are ignored by the positions cache', () async {
      final transport = StreamController<GpsUpdate>();
      final session = ConvoySession(
        selfMemberId: 'me',
        incoming: transport.stream,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(() async {
        await session.dispose();
        await transport.close();
      });

      final snapshots = <Map<String, GpsUpdate>>[];
      final sub = session.positions.listen(snapshots.add);
      addTearDown(sub.cancel);

      session.start();
      transport.add(GpsUpdate(
        memberId: 'peer',
        latitude: 1,
        longitude: 1,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: DateTime.utc(2026, 5, 13, 12, 0, 10),
      ));
      transport.add(GpsUpdate(
        memberId: 'peer',
        latitude: 2,
        longitude: 2,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: DateTime.utc(2026, 5, 13, 12, 0, 5),
      ));

      await Future<void>.delayed(Duration.zero);

      expect(snapshots, hasLength(1));
      expect(session.latestPositions['peer']!.latitude, 1);
    });

    test('latestPositions snapshot is unmodifiable', () async {
      final transport = StreamController<GpsUpdate>();
      final session = ConvoySession(
        selfMemberId: 'me',
        incoming: transport.stream,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(() async {
        await session.dispose();
        await transport.close();
      });

      session.start();
      transport.add(_u('peer', 1, 2));
      await Future<void>.delayed(Duration.zero);

      expect(
        () => session.latestPositions['x'] = _u('x', 0, 0),
        throwsUnsupportedError,
      );
    });

    test('forwards transport errors to gps stream', () async {
      final transport = StreamController<GpsUpdate>();
      final session = ConvoySession(
        selfMemberId: 'me',
        incoming: transport.stream,
        clock: () => DateTime.utc(2026, 5, 13, 12, 0, 0),
      );
      addTearDown(() async {
        await session.dispose();
        await transport.close();
      });

      final errors = <Object>[];
      final sub = session.gpsUpdates.listen(
        (_) {},
        onError: errors.add,
      );
      addTearDown(sub.cancel);

      session.start();
      transport.addError(StateError('boom'));

      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });
  });
}
