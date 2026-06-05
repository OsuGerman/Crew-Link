import 'package:crew_link/features/convoy/domain/waypoint.dart';
import 'package:crew_link/features/convoy/domain/waypoint_tour.dart';
import 'package:crew_link/features/maps/domain/route_geojson.dart';
import 'package:flutter_test/flutter_test.dart';

Waypoint _wp(double lat, double lng, String label) => Waypoint(
      latitude: lat,
      longitude: lng,
      label: label,
      setBy: 'leader',
      setAt: DateTime.utc(2026),
    );

void main() {
  group('buildRouteGeoJson', () {
    test('empty tour → FeatureCollection with no features', () {
      final geo = buildRouteGeoJson(WaypointTour.empty);
      expect(geo['type'], 'FeatureCollection');
      expect(geo['features'], isEmpty);
    });

    test('single stop → one Point, no line, flagged current', () {
      final geo = buildRouteGeoJson(
        WaypointTour(stops: [_wp(48.1, 11.5, 'A')]),
      );
      final features = (geo['features'] as List).cast<Map<String, dynamic>>();
      expect(features, hasLength(1));
      final f = features.single;
      expect((f['geometry'] as Map)['type'], 'Point');
      expect((f['geometry'] as Map)['coordinates'], [11.5, 48.1]);
      expect((f['properties'] as Map)['label'], '1');
      expect((f['properties'] as Map)['isCurrent'], isTrue);
    });

    test('multiple stops → line + numbered points, only first is current', () {
      final geo = buildRouteGeoJson(
        WaypointTour(stops: [
          _wp(48.1, 11.5, 'A'),
          _wp(48.2, 11.6, 'B'),
          _wp(48.3, 11.7, 'C'),
        ]),
      );
      final features = (geo['features'] as List).cast<Map<String, dynamic>>();

      final line = features.firstWhere(
        (f) => (f['geometry'] as Map)['type'] == 'LineString',
      );
      expect((line['geometry'] as Map)['coordinates'], [
        [11.5, 48.1],
        [11.6, 48.2],
        [11.7, 48.3],
      ]);

      final points = features
          .where((f) => (f['geometry'] as Map)['type'] == 'Point')
          .toList();
      expect(points, hasLength(3));
      expect((points[0]['properties'] as Map)['isCurrent'], isTrue);
      expect((points[1]['properties'] as Map)['isCurrent'], isFalse);
      expect((points[2]['properties'] as Map)['isCurrent'], isFalse);
      expect((points[2]['properties'] as Map)['label'], '3');
    });
  });
}
