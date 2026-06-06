import 'package:crew_link/features/convoy/application/waypoint_providers.dart';
import 'package:crew_link/features/convoy/domain/waypoint.dart';
import 'package:crew_link/features/maps/application/maps_providers.dart';
import 'package:crew_link/features/maps/data/road_route_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the waypoints it was asked to route and returns a canned result so
/// the provider's tour→route wiring can be asserted without hitting OSRM.
class _FakeRoadRouteService extends RoadRouteService {
  _FakeRoadRouteService(this._result);

  final RoadRoute? _result;
  final List<List<Waypoint>> calls = [];

  /// When set, the next [fetch] resolves to null (simulates a failed refetch).
  bool failNext = false;

  @override
  Future<RoadRoute?> fetch(List<Waypoint> waypoints) async {
    calls.add(waypoints);
    if (waypoints.length < RoadRouteService.minWaypoints) return null;
    if (failNext) {
      failNext = false;
      return null;
    }
    return _result;
  }
}

Waypoint _wp(double lat, double lng) => Waypoint(
      latitude: lat,
      longitude: lng,
      label: 'S',
      setBy: 'leader',
      setAt: DateTime.utc(2026),
    );

const _route = RoadRoute(
  geometry: [(lat: 48.1, lng: 11.5), (lat: 48.3, lng: 11.7)],
  distanceMeters: 9000,
  durationSeconds: 600,
);

ProviderContainer _container(_FakeRoadRouteService fake) {
  final c = ProviderContainer(
    overrides: [roadRouteServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('roadRouteProvider', () {
    test('stays null while the tour has fewer than two stops', () async {
      final fake = _FakeRoadRouteService(_route);
      final c = _container(fake);
      c.listen(roadRouteProvider, (_, __) {}); // keep alive

      expect(c.read(roadRouteProvider), isNull);

      c.read(tourProvider.notifier).addStop(_wp(48.1, 11.5));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(roadRouteProvider), isNull);
    });

    test('fetches and exposes the road route once two stops exist', () async {
      final fake = _FakeRoadRouteService(_route);
      final c = _container(fake);
      c.listen(roadRouteProvider, (_, __) {});

      c.read(tourProvider.notifier)
        ..addStop(_wp(48.1, 11.5))
        ..addStop(_wp(48.3, 11.7));
      await Future<void>.delayed(Duration.zero);

      final result = c.read(roadRouteProvider);
      expect(result, isNotNull);
      expect(result!.distanceMeters, 9000);
      expect(fake.calls.last, hasLength(2));
    });

    test('clears the route when the tour drops below two stops', () async {
      final fake = _FakeRoadRouteService(_route);
      final c = _container(fake);
      c.listen(roadRouteProvider, (_, __) {});

      c.read(tourProvider.notifier)
        ..addStop(_wp(48.1, 11.5))
        ..addStop(_wp(48.3, 11.7));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(roadRouteProvider), isNotNull);

      c.read(tourProvider.notifier).removeAt(1);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(roadRouteProvider), isNull);
    });

    test('keeps the previous route while a refetch returns null', () async {
      final fake = _FakeRoadRouteService(_route);
      final c = _container(fake);
      c.listen(roadRouteProvider, (_, __) {});

      c.read(tourProvider.notifier)
        ..addStop(_wp(48.1, 11.5))
        ..addStop(_wp(48.3, 11.7));
      await Future<void>.delayed(Duration.zero);
      final first = c.read(roadRouteProvider);
      expect(first, isNotNull);

      // Adding a third stop refetches; the fake now returns null (fetch
      // failure). The previous line must remain so the map doesn't flicker.
      fake.failNext = true;
      c.read(tourProvider.notifier).addStop(_wp(48.5, 11.9));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(roadRouteProvider), same(first));
    });
  });
}
