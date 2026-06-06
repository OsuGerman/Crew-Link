import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';
import '../../convoy/domain/waypoint.dart';

/// A drivable road route through an ordered list of waypoints: the snapped
/// street geometry (for drawing the line) plus the road distance/duration
/// (for a realistic ETA). Immutable + side-effect-free.
class RoadRoute {
  const RoadRoute({
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  /// Polyline of the route along real streets, ordered start → end.
  final List<({double lat, double lng})> geometry;

  /// Total driving distance in metres (OSRM `routes[0].distance`).
  final double distanceMeters;

  /// Total driving duration in seconds (OSRM `routes[0].duration`).
  final double durationSeconds;
}

/// In-app road routing via the OSRM `route` service. Given ≥2 waypoints it
/// returns the street-following geometry + road distance/duration, or `null`
/// on any failure (empty/invalid input, network error, non-200, empty route)
/// so the UI can fall back to the straight-line overlay.
///
/// NOTE: [defaultBaseUrl] points at the public OSRM demo server, which is
/// demo-grade and rate-limited (no SLA, may throttle/ban heavy traffic). For
/// production swap it for a self-hosted OSRM instance or a keyed provider via
/// the constructor's [baseUrl].
class RoadRouteService {
  RoadRouteService({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? defaultBaseUrl,
        _client = client ?? http.Client();

  /// Public OSRM demo server — see the class doc caveat.
  static const String defaultBaseUrl = 'https://router.project-osrm.org';

  /// OSRM needs at least a start and an end coordinate to compute a route.
  static const int minWaypoints = 2;

  final String _baseUrl;
  final http.Client _client;

  /// Fetches the road route through [waypoints] (in order). Returns `null`
  /// when fewer than [minWaypoints] are given, or on any error.
  Future<RoadRoute?> fetch(List<Waypoint> waypoints) async {
    if (waypoints.length < minWaypoints) return null;
    final coords = waypoints
        .map((w) => '${w.longitude},${w.latitude}')
        .join(';');
    final uri = Uri.parse('$_baseUrl/route/v1/driving/$coords').replace(
      queryParameters: const <String, String>{
        'overview': 'full',
        'geometries': 'geojson',
      },
    );
    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return null;
      return _parse(response.body);
    } catch (e, st) {
      appLog.e('RoadRouteService.fetch', error: e, stackTrace: st);
      unawaited(ObservabilityBootstrap.build().reportError(e, st));
      return null;
    }
  }

  /// Parses an OSRM `route` response body. Returns `null` for a missing/empty
  /// `routes` array or an unparseable shape (treated as a no-route, not an
  /// error worth reporting).
  RoadRoute? _parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final routes = decoded['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final route = routes.first;
    if (route is! Map) return null;

    final geometry = route['geometry'];
    if (geometry is! Map) return null;
    final rawCoords = geometry['coordinates'];
    if (rawCoords is! List || rawCoords.isEmpty) return null;

    final points = <({double lat, double lng})>[];
    for (final pair in rawCoords) {
      // OSRM geojson coordinates are [lng, lat].
      if (pair is! List || pair.length < 2) continue;
      final lng = (pair[0] as num).toDouble();
      final lat = (pair[1] as num).toDouble();
      points.add((lat: lat, lng: lng));
    }
    if (points.isEmpty) return null;

    return RoadRoute(
      geometry: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
    );
  }
}

final roadRouteServiceProvider =
    Provider<RoadRouteService>((ref) => RoadRouteService());
