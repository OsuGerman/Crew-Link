import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/models/convoy_member.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/models/vehicle_profile.dart';
import 'package:crew_link/core/theme/app_theme.dart';
import 'package:crew_link/features/convoy/presentation/convoy_member_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GpsUpdate _u(String id, double lat, double lon, {double speed = 0}) =>
    GpsUpdate(
      memberId: id,
      latitude: lat,
      longitude: lon,
      headingDegrees: 0,
      speedMps: speed,
      timestamp: DateTime.utc(2026, 5, 13, 12, 0, 0),
    );

Convoy _convoy({List<ConvoyMember> members = const []}) => Convoy(
      id: 'c1',
      name: 'Trip',
      inviteCode: 'ABC123',
      members: members,
      proximityWarningMeters: 500,
      createdAt: DateTime.utc(2026, 5, 13, 12),
    );

Widget _harness(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, child: child),
      ),
    );

void main() {
  group('ConvoyMemberList', () {
    testWidgets('renders all roster members (offline) when no positions',
        (tester) async {
      final convoy = _convoy(members: const [
        ConvoyMember(id: 'me', displayName: 'Du', isLeader: true),
        ConvoyMember(id: 'buddy', displayName: 'Buddy'),
        ConvoyMember(id: 'lurker', displayName: 'Lurker'),
      ]);
      await tester.pumpWidget(_harness(ConvoyMemberList(
        convoy: convoy,
        positions: const {},
        selfMemberId: 'me',
      )));
      expect(find.text('MITGLIEDER'), findsOneWidget);
      // Members show even without a GPS fix — a joined colleague is visible.
      expect(find.text('0 live · 3 gesamt'), findsOneWidget);
      expect(find.text('Buddy'), findsOneWidget);
      expect(find.text('kein GPS-Signal'), findsWidgets);
    });

    testWidgets('header shows live and total counts when positions present',
        (tester) async {
      final convoy = _convoy(members: const [
        ConvoyMember(id: 'me', displayName: 'Du', isLeader: true),
        ConvoyMember(id: 'buddy', displayName: 'Buddy'),
        ConvoyMember(id: 'lurker', displayName: 'Lurker'),
      ]);
      final positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
        'buddy': _u('buddy', 52.5200, 13.4060),
      };
      await tester.pumpWidget(_harness(ConvoyMemberList(
        convoy: convoy,
        positions: positions,
        selfMemberId: 'me',
      )));
      // 2 members report GPS, 3 are in the convoy roster.
      expect(find.text('2 live · 3 gesamt'), findsOneWidget);
    });

    testWidgets('shows self first, peers sorted by distance ascending',
        (tester) async {
      final convoy = _convoy(members: const [
        ConvoyMember(id: 'me', displayName: 'Du'),
        ConvoyMember(id: 'near', displayName: 'Near'),
        ConvoyMember(id: 'far', displayName: 'Far'),
      ]);
      final positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
        'near': _u('near', 52.5200, 13.4060), // ~78m
        'far': _u('far', 52.5300, 13.4050), // ~1.1km
      };
      await tester.pumpWidget(_harness(ConvoyMemberList(
        convoy: convoy,
        positions: positions,
        selfMemberId: 'me',
      )));

      // Rows are Material widgets keyed 'member-row-<id>', ordered
      // self-first then peers by ascending distance: me, near, far.
      final rowKeys = tester
          .widgetList<Material>(find.byType(Material))
          .where((m) =>
              m.key is ValueKey &&
              (m.key! as ValueKey).value.toString().startsWith('member-row-'))
          .map((m) => (m.key! as ValueKey).value)
          .toList();
      expect(rowKeys, ['member-row-me', 'member-row-near', 'member-row-far']);
    });

    testWidgets('shows Du badge for self and Anführer for leader',
        (tester) async {
      final convoy = _convoy(members: const [
        ConvoyMember(id: 'me', displayName: 'Du'),
        ConvoyMember(id: 'leader', displayName: 'Boss', isLeader: true),
      ]);
      final positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
        'leader': _u('leader', 52.5200, 13.4060),
      };
      await tester.pumpWidget(_harness(ConvoyMemberList(
        convoy: convoy,
        positions: positions,
        selfMemberId: 'me',
      )));

      expect(find.text('Du'), findsWidgets);
      expect(find.text('Leader'), findsOneWidget);
    });

    testWidgets('formats distance and speed in friendly units',
        (tester) async {
      final convoy = _convoy();
      final positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
        'peer': _u('peer', 52.5200, 13.4060, speed: 10),
      };
      await tester.pumpWidget(_harness(ConvoyMemberList(
        convoy: convoy,
        positions: positions,
        selfMemberId: 'me',
      )));

      // ~68 m east, 10 m/s -> 36 km/h
      expect(find.text('68 m'), findsOneWidget);
      expect(find.textContaining('36 km/h'), findsOneWidget);
      // Self row carries the self marker 'Du' (badge + distance pill).
      expect(find.text('Du'), findsWidgets);
    });

    testWidgets('falls back to memberId when convoy.members has no entry',
        (tester) async {
      final convoy = _convoy();
      final positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
        'unlabeled-peer': _u('unlabeled-peer', 52.5300, 13.4050),
      };
      await tester.pumpWidget(_harness(ConvoyMemberList(
        convoy: convoy,
        positions: positions,
        selfMemberId: 'me',
      )));
      expect(find.text('unlabeled-peer'), findsOneWidget);
    });

    testWidgets('yellow gap badge uses dark text, green badge stays white',
        (tester) async {
      final convoy = _convoy(members: const [
        ConvoyMember(id: 'me', displayName: 'Du', isLeader: true),
        ConvoyMember(id: 'near', displayName: 'Near'),
        ConvoyMember(id: 'mid', displayName: 'Mid'),
      ]);
      final positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
        // ~111 m hinterm Leader → grün (< 50 % von 500 m), Ordinal 2.
        'near': _u('near', 52.5210, 13.4050),
        // ~300 m hinterm Leader → gelb (250–500 m), Ordinal 3.
        'mid': _u('mid', 52.5227, 13.4050),
      };
      await tester.pumpWidget(_harness(ConvoyMemberList(
        convoy: convoy,
        positions: positions,
        selfMemberId: 'me',
      )));

      // Weiß auf Amber wäre ~1.6:1 — das gelbe Badge braucht dunklen Text.
      final yellowBadge = tester.widget<Text>(find.text('3'));
      expect(yellowBadge.style?.color, AppColors.background);
      final greenBadge = tester.widget<Text>(find.text('2'));
      expect(greenBadge.style?.color, Colors.white);
    });

    testWidgets('shows vehicle headline when present', (tester) async {
      final convoy = _convoy(members: const [
        ConvoyMember(
          id: 'me',
          displayName: 'Du',
          vehicle: VehicleProfile(
            id: 'v1',
            make: 'Tesla',
            model: 'Model 3',
            year: 2024,
          ),
        ),
        ConvoyMember(
          id: 'buddy',
          displayName: 'Buddy',
          // No vehicle for this peer
        ),
      ]);
      final positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
        'buddy': _u('buddy', 52.5200, 13.4060),
      };
      await tester.pumpWidget(_harness(ConvoyMemberList(
        convoy: convoy,
        positions: positions,
        selfMemberId: 'me',
      )));
      // Vehicle headline and speed share one subtitle Text.
      expect(find.text('Tesla Model 3 · 2024 · 0 km/h'), findsOneWidget);
    });
  });
}
