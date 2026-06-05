import '../../convoy/domain/waypoint_tour.dart';

/// Builds the MapLibre GeoJSON FeatureCollection for the leader-route overlay:
/// a `LineString` through all stops (only when there are ≥2) plus one numbered
/// `Point` per stop. The first stop carries `isCurrent: true` so the map can
/// accent the active target. Pure + side-effect-free so it's unit-testable
/// without a live MapLibre controller.
Map<String, dynamic> buildRouteGeoJson(WaypointTour tour) {
  final stops = tour.stops;
  return {
    'type': 'FeatureCollection',
    'features': [
      if (stops.length >= 2)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final s in stops) [s.longitude, s.latitude],
            ],
          },
          'properties': <String, dynamic>{},
        },
      for (var i = 0; i < stops.length; i++)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [stops[i].longitude, stops[i].latitude],
          },
          'properties': {
            'label': '${i + 1}',
            'isCurrent': i == 0,
          },
        },
    ],
  };
}
