import 'package:crew_link/features/maps/application/maps_providers.dart';
import 'package:crew_link/features/maps/domain/map_viewport.dart';
import 'package:crew_link/features/maps/presentation/convoy_map_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Shared provider for mutating the marker list within a test.
final _testMarkersProvider = StateProvider<List<MemberMarker>>((ref) => const []);

List<MemberMarker> _makeMarkers(
  Map<String, LatLng> positions,
  String selfId,
) =>
    [
      for (final e in positions.entries)
        (memberId: e.key, position: e.value, isSelf: e.key == selfId),
    ];

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ConvoyMapWidget())),
    );

const _defaultViewport = MapViewport(centerLat: 48.137, centerLng: 11.575, zoomLevel: 12);

ProviderContainer _container(List<MemberMarker> initial) => ProviderContainer(
      overrides: [
        _testMarkersProvider.overrideWith((ref) => initial),
        memberMarkersProvider.overrideWith((ref) => ref.watch(_testMarkersProvider)),
        liveViewportProvider.overrideWith((_) => _defaultViewport),
      ],
    );

void main() {
  group('ConvoyMapWidget', () {
    testWidgets('renders self pin and peer pins for each member', (tester) async {
      final container = _container(
        _makeMarkers({'self': LatLng(48.0, 11.0), 'peer': LatLng(48.1, 11.1)}, 'self'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byIcon(Icons.directions_car), findsOneWidget);
    });

    testWidgets('no markers when convoy has no members', (tester) async {
      final container = _container([]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      expect(find.byIcon(Icons.my_location), findsNothing);
      expect(find.byIcon(Icons.directions_car), findsNothing);
    });

    testWidgets('adding a member shows new pin', (tester) async {
      final container = _container(
        _makeMarkers({'self': LatLng(48.0, 11.0)}, 'self'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      expect(find.byIcon(Icons.directions_car), findsNothing);

      container.read(_testMarkersProvider.notifier).state =
          _makeMarkers({'self': LatLng(48.0, 11.0), 'peer': LatLng(48.2, 11.2)}, 'self');
      await tester.pump();

      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byIcon(Icons.directions_car), findsOneWidget);
    });

    testWidgets('removing a member removes pin', (tester) async {
      final container = _container(
        _makeMarkers({'self': LatLng(48.0, 11.0), 'peer': LatLng(48.1, 11.1)}, 'self'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      expect(find.byIcon(Icons.directions_car), findsOneWidget);

      container.read(_testMarkersProvider.notifier).state =
          _makeMarkers({'self': LatLng(48.0, 11.0)}, 'self');
      await tester.pump();

      expect(find.byIcon(Icons.directions_car), findsNothing);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });
  });
}
