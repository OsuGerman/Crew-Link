import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/models/convoy_member.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/presentation/members_sheet_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Convoy _convoy(List<String> memberIds) => Convoy(
      id: 'c1',
      name: 'Trip',
      inviteCode: 'ABC123',
      members: [
        for (final id in memberIds)
          ConvoyMember(id: id, displayName: id, isLeader: id == memberIds.first),
      ],
      proximityWarningMeters: 500,
      createdAt: DateTime.utc(2026, 5, 13, 12),
    );

GpsUpdate _u(String id) => GpsUpdate(
      memberId: id,
      latitude: 52.52,
      longitude: 13.40,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: DateTime.utc(2026, 5, 13, 12),
    );

Widget _wrap(Convoy convoy, Map<String, GpsUpdate> positions,
    {VoidCallback? onTap}) {
  return ProviderScope(
    overrides: [
      livePositionsProvider.overrideWith(
        (ref) => Stream.value(positions),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: MembersSheetPill(convoy: convoy, onTap: onTap ?? () {}),
      ),
    ),
  );
}

void main() {
  group('MembersSheetPill', () {
    testWidgets('shows live count and total roster size', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _convoy(['a', 'b', 'c']),
          {'a': _u('a'), 'b': _u('b')},
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('open-members-sheet')), findsOneWidget);
      expect(find.text('Mitglieder'), findsOneWidget);
      // 2 of 3 members have a live GPS fix.
      expect(find.text('2 live · 3 gesamt'), findsOneWidget);
    });

    testWidgets('total is at least the live count when roster lags',
        (tester) async {
      // Roster only knows 'a', but two members are already broadcasting.
      await tester.pumpWidget(
        _wrap(
          _convoy(['a']),
          {'a': _u('a'), 'b': _u('b')},
        ),
      );
      await tester.pump();

      expect(find.text('2 live · 2 gesamt'), findsOneWidget);
    });

    testWidgets('tapping invokes the onTap callback', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(_convoy(['a']), {'a': _u('a')}, onTap: () => tapped++),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('open-members-sheet')));
      await tester.pump();
      expect(tapped, 1);
    });
  });
}
