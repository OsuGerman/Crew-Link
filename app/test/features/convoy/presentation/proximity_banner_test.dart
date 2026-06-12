import 'dart:async';

import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/models/convoy_member.dart';
import 'package:crew_link/features/convoy/application/active_proximity_warning.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/domain/proximity_warning.dart';
import 'package:crew_link/features/convoy/presentation/proximity_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProximityWarning _warning(String other) => ProximityWarning(
      otherMemberId: other,
      distanceMeters: 50,
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

Widget _harness(StreamController<ProximityWarning> controller, Convoy convoy) {
  return ProviderScope(
    overrides: [
      proximityWarningsProvider.overrideWith((ref) => controller.stream),
      currentConvoyProvider.overrideWith((ref) => convoy),
      // Widget-Test-Pattern: Uhr pinnen, damit zeitabhängige Logik
      // deterministisch bleibt.
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 5, 13, 12)),
    ],
    child: const MaterialApp(home: Scaffold(body: ProximityBanner())),
  );
}

void main() {
  group('ProximityBanner', () {
    testWidgets('shows the roster display name instead of the raw UID',
        (tester) async {
      final controller = StreamController<ProximityWarning>.broadcast();
      addTearDown(controller.close);
      final convoy = _convoy(members: const [
        ConvoyMember(id: 'fbase-uid-0123456789abcdef', displayName: 'Buddy'),
      ]);
      await tester.pumpWidget(_harness(controller, convoy));
      expect(find.byKey(const ValueKey('proximity-banner')), findsNothing);

      controller.add(_warning('fbase-uid-0123456789abcdef'));
      await tester.pump();
      await tester.pump();

      final banner = find.byKey(const ValueKey('proximity-banner'));
      expect(banner, findsOneWidget);
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('Buddy · 50 m entfernt'),
        ),
        findsOneWidget,
      );
      // Die rohe UID taucht nirgends mehr auf.
      expect(
        find.textContaining('fbase-uid-0123456789abcdef'),
        findsNothing,
      );
    });

    testWidgets('falls back to a shortened id for unknown members',
        (tester) async {
      final controller = StreamController<ProximityWarning>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(_harness(controller, _convoy()));

      controller.add(_warning('AbCdEfGhIjKlMnOp'));
      await tester.pump();
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('proximity-banner')),
          matching: find.textContaining('AbCdEfGh…'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('auto-clears after the TTL instead of sticking forever',
        (tester) async {
      final controller = StreamController<ProximityWarning>.broadcast();
      addTearDown(controller.close);
      final convoy = _convoy(members: const [
        ConvoyMember(id: 'buddy', displayName: 'Buddy'),
      ]);
      await tester.pumpWidget(_harness(controller, convoy));

      controller.add(_warning('buddy'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('proximity-banner')), findsOneWidget);

      await tester.pump(kProximityWarningTtl);
      await tester.pump();
      expect(find.byKey(const ValueKey('proximity-banner')), findsNothing);
    });
  });
}
