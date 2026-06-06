import '../../convoy/domain/waypoint_tour.dart';

/// Builds a MapLibre GeoJSON FeatureCollection that draws the route as a single
/// `LineString` along the supplied road [geometry] (real streets, from the OSRM
/// router) plus one numbered `Point` per [tour] stop — the same stop pins as
/// [buildRouteGeoJson], so only the connecting line differs. Used when a road
/// route is available; falls back to [buildRouteGeoJson] otherwise. Pure +
/// side-effect-free so it's unit-testable without a live MapLibre controller.
Map<String, dynamic> buildRoadRouteLineGeoJson(
  WaypointTour tour,
  List<({double lat, double lng})> geometry,
) {
  final stops = tour.stops;
  return {
    'type': 'FeatureCollection',
    'features': [
      if (geometry.length >= 2)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final p in geometry) [p.lng, p.lat],
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
