import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/maps/presentation/convoy_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2024);

final _twoMembers = {
  'alice': GpsUpdate(
    memberId: 'alice',
    latitude: 48.137,
    longitude: 11.575,
    headingDegrees: 0,
    speedMps: 0,
    timestamp: _t0,
  ),
  'bob': GpsUpdate(
    memberId: 'bob',
    latitude: 48.140,
    longitude: 11.580,
    headingDegrees: 90,
    speedMps: 10,
    timestamp: _t0,
  ),
};

ProviderContainer _makeContainer({
  Map<String, GpsUpdate> positions = const {},
  String selfId = 'alice',
}) {
  return ProviderContainer(overrides: [
    livePositionsProvider.overrideWith(
      (ref) => Stream.value(Map<String, GpsUpdate>.unmodifiable(positions)),
    ),
    selfMemberIdProvider.overrideWithValue(selfId),
  ]);
}

Widget _screen(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ConvoyMapScreen()),
    );

void main() {
  group('ConvoyMapScreen', () {
    testWidgets('renders FlutterMap widget', (tester) async {
      final container = _makeContainer(positions: _twoMembers);
      addTearDown(container.dispose);

      await tester.pumpWidget(_screen(container));
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('renders one MarkerLayer', (tester) async {
      final container = _makeContainer(positions: _twoMembers);
      addTearDown(container.dispose);

      await tester.pumpWidget(_screen(container));
      await tester.pump();

      expect(find.byType(MarkerLayer), findsOneWidget);
    });

    testWidgets('renders two member pins for two members', (tester) async {
      final container = _makeContainer(positions: _twoMembers);
      addTearDown(container.dispose);

      await tester.pumpWidget(_screen(container));
      await tester.pump();

      // Each pin renders one Icon — one my_location (self) + one directions_car
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byIcon(Icons.directions_car), findsOneWidget);
    });

    testWidgets('renders no pins when convoy has no members', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_screen(container));
      await tester.pump();

      expect(find.byIcon(Icons.my_location), findsNothing);
      expect(find.byIcon(Icons.directions_car), findsNothing);
    });

    testWidgets('self pin uses my_location icon', (tester) async {
      final container = _makeContainer(
        positions: {
          'me': GpsUpdate(
            memberId: 'me',
            latitude: 48.0,
            longitude: 11.0,
            headingDegrees: 0,
            speedMps: 0,
            timestamp: _t0,
          ),
        },
        selfId: 'me',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_screen(container));
      await tester.pump();

      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byIcon(Icons.directions_car), findsNothing);
    });
  });
}
