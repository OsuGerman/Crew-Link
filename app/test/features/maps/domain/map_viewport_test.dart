import 'package:crew_link/features/maps/domain/map_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapViewport', () {
    test('stores lat/lng/zoom correctly', () {
      const vp = MapViewport(centerLat: 48.1, centerLng: 11.5, zoomLevel: 14);
      expect(vp.centerLat, 48.1);
      expect(vp.centerLng, 11.5);
      expect(vp.zoomLevel, 14);
    });

    test('center getter returns LatLng matching stored values', () {
      const vp = MapViewport(centerLat: 48.1, centerLng: 11.5, zoomLevel: 14);
      expect(vp.center.latitude, 48.1);
      expect(vp.center.longitude, 11.5);
    });

    group('fitPositions', () {
      test('empty list falls back to default city-centre viewport', () {
        final vp = MapViewport.fitPositions([]);
        expect(vp.zoomLevel, 12);
        expect(vp.centerLat, closeTo(48.137, 0.001));
        expect(vp.centerLng, closeTo(11.575, 0.001));
      });

      test('single position uses default zoom', () {
        final vp = MapViewport.fitPositions([(lat: 52.0, lng: 13.0)]);
        expect(vp.centerLat, 52.0);
        expect(vp.centerLng, 13.0);
        expect(vp.zoomLevel, 14);
      });

      test('two nearby positions (<= 500 m) produce high zoom', () {
        // ~450 m apart horizontally at 48° latitude
        final vp = MapViewport.fitPositions([
          (lat: 48.000, lng: 11.000),
          (lat: 48.000, lng: 11.005),
        ]);
        expect(vp.centerLat, closeTo(48.0, 0.0001));
        expect(vp.centerLng, closeTo(11.0025, 0.0001));
        expect(vp.zoomLevel, greaterThanOrEqualTo(13.0));
      });

      test('positions ~10 km apart produce medium zoom', () {
        final vp = MapViewport.fitPositions([
          (lat: 48.0, lng: 11.0),
          (lat: 48.09, lng: 11.09),
        ]);
        expect(vp.centerLat, closeTo(48.045, 0.001));
        expect(vp.centerLng, closeTo(11.045, 0.001));
        expect(vp.zoomLevel, lessThanOrEqualTo(13.0));
        expect(vp.zoomLevel, greaterThanOrEqualTo(10.0));
      });

      test('positions >200 km apart produce low zoom', () {
        final vp = MapViewport.fitPositions([
          (lat: 47.0, lng: 10.0),
          (lat: 53.0, lng: 14.0),
        ]);
        expect(vp.zoomLevel, lessThanOrEqualTo(8.0));
      });

      test('centre is the geometric midpoint of all positions', () {
        final vp = MapViewport.fitPositions([
          (lat: 10.0, lng: 20.0),
          (lat: 20.0, lng: 40.0),
          (lat: 30.0, lng: 60.0),
        ]);
        expect(vp.centerLat, closeTo(20.0, 0.0001));
        expect(vp.centerLng, closeTo(40.0, 0.0001));
      });
    });
  });
}
