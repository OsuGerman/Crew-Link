import 'dart:async';

import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/models/convoy_member.dart';
import 'package:crew_link/features/convoy/application/active_proximity_warning.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/domain/proximity_warning.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProximityWarning _warning({String other = 'buddy', double distance = 50}) =>
    ProximityWarning(
      otherMemberId: other,
      distanceMeters: distance,
      thresholdMeters: 500,
      triggeredAt: DateTime.utc(2026, 5, 13, 12),
    );

Convoy _convoy({List<ConvoyMember> members = const []}) => Convoy(
      id: 'c1',
      name: 'Trip',
      inviteCode: 'ABC123',
      members: members,
      proximityWarningMeters: 500,
      createdAt: DateTime.utc(2026, 5, 13, 12),
    );

void main() {
  group('activeProximityWarningProvider', () {
    test('holds the latest warning and auto-clears after the TTL', () {
      fakeAsync((async) {
        final controller = StreamController<ProximityWarning>(sync: true);
        final container = ProviderContainer(overrides: [
          proximityWarningsProvider.overrideWith((ref) => controller.stream),
        ]);
        container.listen<ProximityWarning?>(
          activeProximityWarningProvider,
          (_, __) {},
        );
        async.flushMicrotasks();
        expect(container.read(activeProximityWarningProvider), isNull);

        controller.add(_warning());
        async.flushMicrotasks();
        expect(
          container.read(activeProximityWarningProvider)?.otherMemberId,
          'buddy',
        );

        async.elapse(kProximityWarningTtl);
        expect(container.read(activeProximityWarningProvider), isNull);

        container.dispose();
        unawaited(controller.close());
      });
    });

    test('a fresh warning resets the clear timer', () {
      fakeAsync((async) {
        final controller = StreamController<ProximityWarning>(sync: true);
        final container = ProviderContainer(overrides: [
          proximityWarningsProvider.overrideWith((ref) => controller.stream),
        ]);
        container.listen<ProximityWarning?>(
          activeProximityWarningProvider,
          (_, __) {},
        );
        async.flushMicrotasks();

        controller.add(_warning(other: 'first'));
        async.flushMicrotasks();
        // Kurz vor Ablauf kommt eine neue Warnung — der Timer startet neu.
        async.elapse(kProximityWarningTtl - const Duration(seconds: 1));
        controller.add(_warning(other: 'second'));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 2));
        expect(
          container.read(activeProximityWarningProvider)?.otherMemberId,
          'second',
        );

        async.elapse(kProximityWarningTtl);
        expect(container.read(activeProximityWarningProvider), isNull);

        container.dispose();
        unawaited(controller.close());
      });
    });
  });

  group('memberDisplayName', () {
    test('resolves the roster display name', () {
      final convoy = _convoy(members: const [
        ConvoyMember(id: 'uid-123456789', displayName: 'Buddy'),
      ]);
      expect(memberDisplayName(convoy, 'uid-123456789'), 'Buddy');
    });

    test('falls back to a shortened id when not in the roster', () {
      expect(
        memberDisplayName(_convoy(), 'AbCdEfGhIjKlMnOp'),
        'AbCdEfGh…',
      );
    });

    test('keeps short ids untouched and handles a null convoy', () {
      expect(memberDisplayName(null, 'buddy'), 'buddy');
    });
  });
}
