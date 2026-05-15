import 'dart:math' as math;

/// Great-circle distance in meters between two WGS84 coordinates.
///
/// Used for proximity warnings on the client. Server-side geo-queries
/// run via PostGIS (per project rule), so this client helper is only
/// for local UX (warning haptics, in-app banners) — not authoritative.
double haversineMeters({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final lat1Rad = _toRadians(lat1);
  final lat2Rad = _toRadians(lat2);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLon / 2) * math.sin(dLon / 2) *
          math.cos(lat1Rad) * math.cos(lat2Rad);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

/// Initial bearing (forward azimuth) in degrees from point 1 to point
/// 2, clockwise from true north — i.e. 0° = north, 90° = east.
///
/// Used by the radar view to place peer markers around the self icon.
double bearingDegrees({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  final phi1 = _toRadians(lat1);
  final phi2 = _toRadians(lat2);
  final dLambda = _toRadians(lon2 - lon1);
  final y = math.sin(dLambda) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  final theta = math.atan2(y, x);
  return (theta * 180.0 / math.pi + 360.0) % 360.0;
}

double _toRadians(double degrees) => degrees * math.pi / 180.0;
