import 'package:crew_link/features/convoy/domain/route_eta.dart';
import 'package:crew_link/features/convoy/domain/waypoint_tour.dart';
import 'package:flutter_test/flutter_test.dart';

WaypointTour _tour(List<List<double>> coords) => WaypointTour.fromJson({
      'stops': [
        for (final c in coords)
          {
            'latitude': c[0],
            'longitude': c[1],
            'label': 'S',
            'setBy': 'u',
            'setAt': '2026-06-06T12:00:00Z',
          },
      ],
    });

void main() {
  group('computeRouteEtas', () {
    test('accumulates distance and time per stop', () {
      // Two stops 0.5° east apart at 48°N (~37 km each). At 60 km/h the minute
      // count equals the km count.
      final etas = computeRouteEtas(
        tour: _tour([
          [48.0, 11.5],
          [48.0, 12.0],
        ]),
        fromLat: 48.0,
        fromLng: 11.0,
        avgSpeedKmh: 60,
      );
      expect(etas.length, 2);
      expect(etas[0].cumulativeKm, closeTo(37.2, 1.5));
      expect(etas[1].cumulativeKm, closeTo(74.4, 2.5));
      expect(etas[1].cumulativeKm, greaterThan(etas[0].cumulativeKm));
      expect(etas[1].duration.inMinutes, closeTo(74, 4));
    });

    test('empty tour or zero speed yields no etas', () {
      expect(
        computeRouteEtas(tour: WaypointTour.empty, fromLat: 0, fromLng: 0),
        isEmpty,
      );
      expect(
        computeRouteEtas(
          tour: _tour([
            [48.0, 11.5],
          ]),
          fromLat: 48.0,
          fromLng: 11.0,
          avgSpeedKmh: 0,
        ),
        isEmpty,
      );
    });
  });

  group('formatRouteDuration', () {
    test('formats minutes-only and hours+minutes', () {
      expect(formatRouteDuration(const Duration(minutes: 45)), '45 min');
      expect(formatRouteDuration(const Duration(minutes: 130)), '2 h 10 min');
    });
  });
}
