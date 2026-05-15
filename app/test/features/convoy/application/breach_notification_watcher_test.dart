import 'dart:async';

import 'package:crew_link/core/models/breach_event.dart';
import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/models/convoy_member.dart';
import 'package:crew_link/core/notifications/breach_broadcast_repository.dart';
import 'package:crew_link/core/notifications/notification_service.dart';
import 'package:crew_link/features/convoy/application/breach_notification_watcher.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/domain/proximity_warning.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeNotificationService implements NotificationService {
  final shown = <({int id, String title, String body})>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async =>
      shown.add((id: id, title: title, body: body));

  @override
  Future<void> showSplit({
    required int id,
    required String memberName,
    required double distanceMeters,
  }) async {}

  @override
  Future<void> showConnectionLost({
    required int notificationId,
    required String memberName,
    required double thresholdMeters,
  }) async {}
}

class _FakeBreachRepository implements BreachBroadcastRepository {
  final published = <({
    String convoyId,
    String memberAId,
    String memberBId,
    double distanceMeters
  })>[];
  final _ctrl = StreamController<BreachEvent>.broadcast();

  @override
  Future<void> publish({
    required String convoyId,
    required String memberAId,
    required String memberBId,
    required double distanceMeters,
    DateTime Function()? clock,
  }) async =>
      published.add((
        convoyId: convoyId,
        memberAId: memberAId,
        memberBId: memberBId,
        distanceMeters: distanceMeters,
      ));

  @override
  Stream<BreachEvent> incoming(String convoyId) => _ctrl.stream;

  void emit(BreachEvent event) => _ctrl.add(event);

  Future<void> close() => _ctrl.close();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Convoy _convoy({List<ConvoyMember> members = const []}) => Convoy(
      id: 'convoy-1',
      name: 'Test Konvoi',
      inviteCode: 'ABCD',
      members: members,
      proximityWarningMeters: 500,
      createdAt: DateTime(2026),
    );

ProximityWarning _warning(String memberId, double distance) => ProximityWarning(
      otherMemberId: memberId,
      distanceMeters: distance,
      thresholdMeters: 500,
      triggeredAt: DateTime.utc(2026, 5, 14),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('breachNotificationWatcherProvider', () {
    late _FakeNotificationService fakeNotif;
    late _FakeBreachRepository fakeRepo;
    late StreamController<ProximityWarning> warningCtrl;

    setUp(() {
      fakeNotif = _FakeNotificationService();
      fakeRepo = _FakeBreachRepository();
      warningCtrl = StreamController<ProximityWarning>.broadcast();
    });

    tearDown(() async {
      warningCtrl.close();
      await fakeRepo.close();
    });

    ProviderContainer buildContainer({Convoy? convoy}) => ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(fakeNotif),
            breachBroadcastRepositoryProvider.overrideWithValue(fakeRepo),
            selfMemberIdProvider.overrideWithValue('self'),
            currentConvoyProvider.overrideWith((_) => convoy),
            proximityWarningsProvider.overrideWith((_) => warningCtrl.stream),
          ],
        );

    test('fires local notification when a proximity warning is emitted',
        () async {
      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});

      warningCtrl.add(_warning('peer-1', 123));
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.shown, hasLength(1));
      expect(fakeNotif.shown.single.title, 'Konvoi-Warnung');
      expect(fakeNotif.shown.single.body, contains('peer-1'));
      expect(fakeNotif.shown.single.body, contains('123'));
    });

    test('uses display name from convoy member list', () async {
      final convoy = _convoy(members: [
        const ConvoyMember(id: 'self', displayName: 'Fahrer A'),
        const ConvoyMember(id: 'peer-1', displayName: 'Fahrer B'),
      ]);
      final container = buildContainer(convoy: convoy);
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});

      warningCtrl.add(_warning('peer-1', 750));
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.shown.single.body, contains('Fahrer B'));
    });

    test('falls back to member id when display name is unknown', () async {
      final container =
          buildContainer(convoy: _convoy(members: []));
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});

      warningCtrl.add(_warning('unknown-peer', 550));
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.shown.single.body, contains('unknown-peer'));
    });

    test('broadcasts to RTDB on proximity warning', () async {
      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});

      warningCtrl.add(_warning('peer', 600));
      await Future<void>.delayed(Duration.zero);

      expect(fakeRepo.published, hasLength(1));
      expect(fakeRepo.published.first.convoyId, 'convoy-1');
      expect(fakeRepo.published.first.memberAId, 'self');
      expect(fakeRepo.published.first.memberBId, 'peer');
    });

    test('shows one notification per member breach', () async {
      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});

      warningCtrl.add(_warning('peer-a', 100));
      warningCtrl.add(_warning('peer-b', 200));
      warningCtrl.add(_warning('peer-c', 300));
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.shown, hasLength(3));
    });

    test('same member id produces the same notification id', () async {
      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});

      warningCtrl.add(_warning('peer-x', 200));
      warningCtrl.add(_warning('peer-x', 250));
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.shown[0].id, equals(fakeNotif.shown[1].id));
    });

    test('shows notification for foreign breach (neither member is self)',
        () async {
      final convoy = _convoy(members: [
        const ConvoyMember(id: 'self', displayName: 'Fahrer A'),
        const ConvoyMember(id: 'other1', displayName: 'Fahrer B'),
        const ConvoyMember(id: 'other2', displayName: 'Fahrer C'),
      ]);
      final container = buildContainer(convoy: convoy);
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});

      fakeRepo.emit(BreachEvent(
        id: 'other1__other2',
        convoyId: 'convoy-1',
        memberAId: 'other1',
        memberBId: 'other2',
        distanceMeters: 820,
        triggeredAt: DateTime(2026),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.shown, hasLength(1));
      expect(fakeNotif.shown.first.body, contains('Fahrer B'));
      expect(fakeNotif.shown.first.body, contains('Fahrer C'));
    });

    test('skips incoming breach where self is a member', () async {
      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});

      fakeRepo.emit(BreachEvent(
        id: 'peer__self',
        convoyId: 'convoy-1',
        memberAId: 'peer',
        memberBId: 'self',
        distanceMeters: 600,
        triggeredAt: DateTime(2026),
      ));
      await Future<void>.delayed(Duration.zero);

      // Self already received the local notification from ProximityWarning.
      expect(fakeNotif.shown, isEmpty);
    });

    test('no notification fired when no warning is emitted', () async {
      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.shown, isEmpty);
    });

    test('notification body includes distance in whole meters', () async {
      final container = buildContainer(convoy: _convoy());
      addTearDown(container.dispose);
      container.listen(breachNotificationWatcherProvider, (_, __) {});

      warningCtrl.add(_warning('peer-1', 456.789));
      await Future<void>.delayed(Duration.zero);

      expect(fakeNotif.shown.single.body, contains('457'));
    });
  });

  group('BreachEvent', () {
    test('pairKey is commutative', () {
      expect(
        BreachEvent.pairKey('member-aaa', 'member-bbb'),
        BreachEvent.pairKey('member-bbb', 'member-aaa'),
      );
    });

    test('toRtdb round-trips through fromRtdb', () {
      final original = BreachEvent(
        id: 'aaa__bbb',
        convoyId: 'c1',
        memberAId: 'aaa',
        memberBId: 'bbb',
        distanceMeters: 750.5,
        triggeredAt: DateTime.utc(2026, 5, 14, 12),
      );
      final restored =
          BreachEvent.fromRtdb('aaa__bbb', 'c1', original.toRtdb());
      expect(restored.memberAId, original.memberAId);
      expect(restored.memberBId, original.memberBId);
      expect(restored.distanceMeters, original.distanceMeters);
      expect(restored.triggeredAt, original.triggeredAt);
    });
  });
}
