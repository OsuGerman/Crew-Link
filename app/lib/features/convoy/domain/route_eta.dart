import '../../../core/geo/geo_distance.dart';
import 'waypoint_tour.dart';

/// Cumulative distance + travel-time estimate to one route stop.
class StopEta {
  const StopEta({required this.cumulativeKm, required this.duration});

  final double cumulativeKm;
  final Duration duration;
}

/// Rough ETA per stop, walking the tour from [fromLat]/[fromLng] and dividing
/// the accumulated great-circle distance by [avgSpeedKmh]. Distances are
/// straight-line (consistent with the route display) — an estimate, not
/// turn-by-turn routing. Returns an empty list for an empty tour or a
/// non-positive speed.
List<StopEta> computeRouteEtas({
  required WaypointTour tour,
  required double fromLat,
  required double fromLng,
  double avgSpeedKmh = 65,
}) {
  if (tour.stops.isEmpty || avgSpeedKmh <= 0) return const <StopEta>[];
  final etas = <StopEta>[];
  var cumulativeMeters = 0.0;
  var prevLat = fromLat;
  var prevLng = fromLng;
  for (final stop in tour.stops) {
    cumulativeMeters += haversineMeters(
      lat1: prevLat,
      lon1: prevLng,
      lat2: stop.latitude,
      lon2: stop.longitude,
    );
    final km = cumulativeMeters / 1000;
    etas.add(StopEta(
      cumulativeKm: km,
      duration: Duration(minutes: (km / avgSpeedKmh * 60).round()),
    ));
    prevLat = stop.latitude;
    prevLng = stop.longitude;
  }
  return etas;
}

/// Total-route ETA built from OSRM road [distanceMeters] / [durationSeconds]
/// (real streets), used in place of the straight-line sum when a road route is
/// available. Both inputs must be non-negative.
StopEta roadRouteTotalEta({
  required double distanceMeters,
  required double durationSeconds,
}) =>
    StopEta(
      cumulativeKm: distanceMeters / 1000,
      duration: Duration(seconds: durationSeconds.round()),
    );

/// "45 min" / "2 h 10 min".
String formatRouteDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h == 0 ? '$m min' : '$h h $m min';
}
