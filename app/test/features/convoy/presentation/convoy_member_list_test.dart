import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/models/convoy_member.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/models/vehicle_profile.dart';
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
    testWidgets('renders header with member count from convoy.members',
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
      expect(find.text('3 Mitglieder im Konvoi'), findsOneWidget);
      expect(find.text('noch keine Live-GPS-Daten'), findsOneWidget);
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

      final tiles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .toList();
      // Header tile is index 0; member rows follow in order me, near, far.
      expect((tiles[1].key as ValueKey).value, 'member-row-me');
      expect((tiles[2].key as ValueKey).value, 'member-row-near');
      expect((tiles[3].key as ValueKey).value, 'member-row-far');
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
      expect(find.text('Anführer'), findsOneWidget);
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

      // ~78 m east, 10 m/s -> 36 km/h
      expect(find.textContaining('m entfernt'), findsOneWidget);
      expect(find.textContaining('36 km/h'), findsOneWidget);
      expect(find.textContaining('Du · hier'), findsOneWidget);
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
      expect(find.text('Tesla Model 3 · 2024'), findsOneWidget);
    });
  });
}
