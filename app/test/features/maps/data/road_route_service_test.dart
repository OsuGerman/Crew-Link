import 'package:crew_link/features/convoy/domain/waypoint.dart';
import 'package:crew_link/features/maps/data/road_route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Waypoint _wp(double lat, double lng) => Waypoint(
      latitude: lat,
      longitude: lng,
      label: 'S',
      setBy: 'leader',
      setAt: DateTime.utc(2026),
    );

// Trimmed but real-shaped OSRM /route response (geojson geometry = [lng,lat]).
const _okBody = '{"code":"Ok","routes":[{"distance":12450.7,'
    '"duration":845.3,"geometry":{"type":"LineString","coordinates":'
    '[[11.5,48.1],[11.55,48.15],[11.6,48.2]]}}],"waypoints":[]}';

void main() {
  group('RoadRouteService.fetch', () {
    test('parses geometry, distance and duration; sends ordered coords',
        () async {
      late Uri captured;
      final service = RoadRouteService(
        client: MockClient((req) async {
          captured = req.url;
          return http.Response(_okBody, 200);
        }),
      );

      final route = await service.fetch([_wp(48.1, 11.5), _wp(48.2, 11.6)]);

      // OSRM path uses lng,lat order, semicolon-separated, in tour order.
      expect(captured.path, contains('/route/v1/driving/11.5,48.1;11.6,48.2'));
      expect(captured.queryParameters['overview'], 'full');
      expect(captured.queryParameters['geometries'], 'geojson');

      expect(route, isNotNull);
      expect(route!.distanceMeters, closeTo(12450.7, 0.001));
      expect(route.durationSeconds, closeTo(845.3, 0.001));
      expect(route.geometry, hasLength(3));
      // [lng,lat] in the wire is flipped to (lat,lng).
      expect(route.geometry.first.lat, closeTo(48.1, 0.0001));
      expect(route.geometry.first.lng, closeTo(11.5, 0.0001));
      expect(route.geometry.last.lat, closeTo(48.2, 0.0001));
      expect(route.geometry.last.lng, closeTo(11.6, 0.0001));
    });

    test('returns null for fewer than two waypoints (no request made)',
        () async {
      var called = false;
      final service = RoadRouteService(
        client: MockClient((_) async {
          called = true;
          return http.Response(_okBody, 200);
        }),
      );
      expect(await service.fetch([_wp(48.1, 11.5)]), isNull);
      expect(await service.fetch(const []), isNull);
      expect(called, isFalse);
    });

    test('returns null on a non-200 response', () async {
      final service = RoadRouteService(
        client: MockClient((_) async => http.Response('busy', 503)),
      );
      expect(
        await service.fetch([_wp(48.1, 11.5), _wp(48.2, 11.6)]),
        isNull,
      );
    });

    test('returns null on an empty routes array', () async {
      final service = RoadRouteService(
        client: MockClient(
          (_) async => http.Response('{"code":"NoRoute","routes":[]}', 200),
        ),
      );
      expect(
        await service.fetch([_wp(48.1, 11.5), _wp(48.2, 11.6)]),
        isNull,
      );
    });

    test('returns null on a network error (still graceful)', () async {
      final service = RoadRouteService(
        client: MockClient((_) async => throw const _BoomException()),
      );
      expect(
        await service.fetch([_wp(48.1, 11.5), _wp(48.2, 11.6)]),
        isNull,
      );
    });

    test('uses the configurable base url', () async {
      late Uri captured;
      final service = RoadRouteService(
        baseUrl: 'https://osrm.example.test',
        client: MockClient((req) async {
          captured = req.url;
          return http.Response(_okBody, 200);
        }),
      );
      await service.fetch([_wp(48.1, 11.5), _wp(48.2, 11.6)]);
      expect(captured.origin, 'https://osrm.example.test');
    });
  });
}

class _BoomException implements Exception {
  const _BoomException();
}
