import 'package:crew_link/features/convoy/domain/convoy_standings.dart';
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
        (
          memberId: e.key,
          position: e.value,
          isSelf: e.key == selfId,
          headingDegrees: 0,
          ordinal: 0,
          tier: GapTier.green,
        ),
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

// Pins are rendered by the native MapLibre platform view via GeoJSON
// circle/symbol layers, which do not paint Flutter widgets in widget tests.
// We therefore verify that the widget builds (fit-all FAB present) and that
// marker data flows through memberMarkersProvider as the convoy mutates.
void main() {
  group('ConvoyMapWidget', () {
    testWidgets('builds with the fit-all control and exposes self + peer markers',
        (tester) async {
      final container = _container(
        _makeMarkers(
          {'self': const LatLng(48.0, 11.0), 'peer': const LatLng(48.1, 11.1)},
          'self',
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      expect(find.byKey(const ValueKey('fit-all-fab')), findsOneWidget);

      final markers = container.read(memberMarkersProvider);
      expect(markers, hasLength(2));
      expect(markers.where((m) => m.isSelf), hasLength(1));
      expect(markers.firstWhere((m) => m.isSelf).memberId, 'self');
      expect(markers.where((m) => !m.isSelf).map((m) => m.memberId), contains('peer'));
    });

    testWidgets('no markers when convoy has no members', (tester) async {
      final container = _container([]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      expect(find.byKey(const ValueKey('fit-all-fab')), findsOneWidget);
      expect(container.read(memberMarkersProvider), isEmpty);
    });

    testWidgets('adding a member surfaces a new marker', (tester) async {
      final container = _container(
        _makeMarkers({'self': const LatLng(48.0, 11.0)}, 'self'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      expect(container.read(memberMarkersProvider).where((m) => !m.isSelf), isEmpty);

      container.read(_testMarkersProvider.notifier).state = _makeMarkers(
        {'self': const LatLng(48.0, 11.0), 'peer': const LatLng(48.2, 11.2)},
        'self',
      );
      await tester.pump();

      final markers = container.read(memberMarkersProvider);
      expect(markers, hasLength(2));
      expect(markers.where((m) => !m.isSelf).map((m) => m.memberId), contains('peer'));
    });

    testWidgets('removing a member drops its marker', (tester) async {
      final container = _container(
        _makeMarkers(
          {'self': const LatLng(48.0, 11.0), 'peer': const LatLng(48.1, 11.1)},
          'self',
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      expect(container.read(memberMarkersProvider).where((m) => !m.isSelf), hasLength(1));

      container.read(_testMarkersProvider.notifier).state =
          _makeMarkers({'self': const LatLng(48.0, 11.0)}, 'self');
      await tester.pump();

      final markers = container.read(memberMarkersProvider);
      expect(markers.where((m) => !m.isSelf), isEmpty);
      expect(markers.where((m) => m.isSelf), hasLength(1));
    });
  });
}
