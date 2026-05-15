import 'dart:async';

import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/models/convoy_member.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/notifications/notification_service.dart';
import 'package:crew_link/features/convoy/application/breach_notification_watcher.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/application/convoy_split_watcher.dart';
import 'package:crew_link/features/convoy/domain/convoy_split_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeNotificationService implements NotificationService {
  final splits = <({int id, String memberName, double distanceMeters})>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> showSplit({
    required int id,
    required String memberName,
    required double distanceMeters,
  }) async =>
      splits.add((id: id, memberName: memberName, distanceMeters: distanceMeters));

  @override
  Future<void> showConnectionLost({
    required int notificationId,
    required String memberName,
    required double thresholdMeters,
  }) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Convoy _convoy({
  List<ConvoyMember> members = const [],
  double thresholdMeters = 500,
}) =>
    Convoy(
      id: 'convoy-1',
      name: 'Test Konvoi',
      inviteCode: 'ABCD',
      members: members,
      proximityWarningMeters: thresholdMeters,
      createdAt: DateTime(2026),
    );

GpsUpdate _pos(String memberId, {double lat = 0, double lon = 0}) => GpsUpdate(
      memberId: memberId,
      latitude: lat,
      longitude: lon,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: DateTime.utc(2026, 5, 14),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('convoySplitWatcherProvider', () {
    late _FakeNotificationService fakeNotif;
    late StreamController<AsyncValue<Map<String, GpsUpdate>>> posCtrl;
    late DateTime Function() fakeClock;

    setUp(() {
      fakeNotif = _FakeNotificationService();
      posCtrl =
          StreamController<AsyncValue<Map<String, GpsUpdate>>>.broadcast();
      fakeClock = () => DateTime.utc(2026, 5, 14, 12);
    });

    tearDown(() async {
      await posCtrl.close();
    });

    ProviderContainer buildContainer({Convoy? convoy}) => ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(fakeNotif),
            selfMemberIdProvider.overrideWithValue('self'),
            currentConvoyProvider.overrideWith((_) => convoy),
            clockProvider.overrideWith((_) => fakeClock),
            livePositionsProvider.overrideWith(
              (_) => posCtrl.stream
                  .map((v) => v.valueOrNull ?? const {}),
            ),
          ],
        );

    void emit(Map<String, GpsUpdate> positions) =>
        posCtrl.add(AsyncData(positions));

    test('no split declared before sustained threshold is reached', () async {
      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(convoySplitWatcherProvider, (_, __) {});

      // peer is far away but only for 0 s (same tick)
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      expect(container.read(activeSplitProvider), isNull);
      expect(fakeNotif.splits, isEmpty);
    });

    test('declares split after sustained breach of kSustainedSeconds', () async {
      final t0 = DateTime.utc(2026, 5, 14, 12);
      fakeClock = () => t0;

      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(convoySplitWatcherProvider, (_, __) {});

      // First position: breach starts
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      // Advance clock past threshold and emit again
      fakeClock = () => t0.add(
            const Duration(seconds: ConvoySplitEvent.kSustainedSeconds),
          );
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      expect(container.read(activeSplitProvider), isNotNull);
      expect(
          container.read(activeSplitProvider)!.splitMemberId, equals('peer'));
      expect(fakeNotif.splits, hasLength(1));
    });

    test('resets breach timer when member returns within threshold', () async {
      final t0 = DateTime.utc(2026, 5, 14, 12);
      fakeClock = () => t0;

      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(convoySplitWatcherProvider, (_, __) {});

      // Breach starts
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      // Member comes back within threshold — timer clears
      emit({'self': _pos('self'), 'peer': _pos('peer')});
      await Future<void>.delayed(Duration.zero);

      // Advance past threshold and emit again
      fakeClock =
          () => t0.add(const Duration(seconds: ConvoySplitEvent.kSustainedSeconds));
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      // Not a split yet — timer was reset when member returned
      expect(container.read(activeSplitProvider), isNull);
      expect(fakeNotif.splits, isEmpty);
    });

    test('cooldown prevents re-trigger within 5 minutes', () async {
      final t0 = DateTime.utc(2026, 5, 14, 12);
      fakeClock = () => t0;

      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(convoySplitWatcherProvider, (_, __) {});

      // First split fires
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);
      fakeClock =
          () => t0.add(const Duration(seconds: ConvoySplitEvent.kSustainedSeconds));
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);
      expect(fakeNotif.splits, hasLength(1));

      // Advance 60 s only (within 5 min cooldown) — should not re-fire
      fakeClock = () => t0.add(const Duration(seconds: 90));
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.splits, hasLength(1));
    });

    test('re-fires after cooldown expires', () async {
      final t0 = DateTime.utc(2026, 5, 14, 12);
      fakeClock = () => t0;

      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(convoySplitWatcherProvider, (_, __) {});

      // First split
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);
      fakeClock =
          () => t0.add(const Duration(seconds: ConvoySplitEvent.kSustainedSeconds));
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);
      expect(fakeNotif.splits, hasLength(1));

      // Advance past cooldown (>300 s) and trigger breach again
      final t1 =
          t0.add(const Duration(seconds: ConvoySplitEvent.kSustainedSeconds + 301));
      fakeClock = () => t1;
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.splits, hasLength(2));
    });

    test('uses display name in push notification', () async {
      final t0 = DateTime.utc(2026, 5, 14, 12);
      fakeClock = () => t0;

      final convoy = _convoy(members: [
        const ConvoyMember(id: 'self', displayName: 'Fahrer A'),
        const ConvoyMember(id: 'peer', displayName: 'Fahrer B'),
      ]);
      final container = buildContainer(convoy: convoy);
      addTearDown(container.dispose);
      container.listen(convoySplitWatcherProvider, (_, __) {});

      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);
      fakeClock =
          () => t0.add(const Duration(seconds: ConvoySplitEvent.kSustainedSeconds));
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.splits.single.memberName, equals('Fahrer B'));
    });

    test('falls back to member id when display name is unknown', () async {
      final t0 = DateTime.utc(2026, 5, 14, 12);
      fakeClock = () => t0;

      final container = buildContainer(convoy: _convoy(members: []));
      addTearDown(container.dispose);
      container.listen(convoySplitWatcherProvider, (_, __) {});

      emit({'self': _pos('self'), 'unknown': _pos('unknown', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);
      fakeClock =
          () => t0.add(const Duration(seconds: ConvoySplitEvent.kSustainedSeconds));
      emit({'self': _pos('self'), 'unknown': _pos('unknown', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.splits.single.memberName, equals('unknown'));
    });

    test('split notification id is in the reserved offset range', () async {
      final t0 = DateTime.utc(2026, 5, 14, 12);
      fakeClock = () => t0;

      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(convoySplitWatcherProvider, (_, __) {});

      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);
      fakeClock =
          () => t0.add(const Duration(seconds: ConvoySplitEvent.kSustainedSeconds));
      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.splits.single.id, greaterThanOrEqualTo(100000));
      expect(fakeNotif.splits.single.id, lessThan(200000));
    });

    test('no action when no convoy is active', () async {
      final container = buildContainer(convoy: null);
      addTearDown(container.dispose);
      container.listen(convoySplitWatcherProvider, (_, __) {});

      emit({'self': _pos('self'), 'peer': _pos('peer', lon: 0.01)});
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.splits, isEmpty);
    });
  });
}
