import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/gps_update.dart';
import '../../convoy/application/convoy_providers.dart';
import '../../convoy/application/waypoint_providers.dart';
import '../../convoy/domain/convoy_standings.dart';
import '../../convoy/domain/waypoint_tour.dart';
import '../data/road_route_service.dart';
import '../domain/map_viewport.dart';

typedef MemberMarker = ({
  String memberId,
  LatLng position,
  bool isSelf,
  double headingDegrees,
  int ordinal,
  GapTier tier,
});

/// Live list of map markers derived from the active convoy session. Each entry
/// carries the member id, current LatLng, heading, self-flag, plus the member's
/// convoy ordinal (#1 = leader) and green/yellow/red gap tier for numbered,
/// colour-coded pins.
final memberMarkersProvider = Provider.autoDispose<List<MemberMarker>>((ref) {
  final Map<String, GpsUpdate> positions =
      ref.watch(livePositionsProvider).valueOrNull ?? const <String, GpsUpdate>{};
  final selfId = ref.watch(selfMemberIdProvider);
  final convoy = ref.watch(currentConvoyProvider);
  final standings = convoy == null
      ? const <String, MemberStanding>{}
      : computeConvoyStandings(
          members: convoy.members,
          positions: positions,
          thresholdMeters: convoy.proximityWarningMeters,
        );
  return [
    for (final entry in positions.entries)
      (
        memberId: entry.key,
        position: LatLng(entry.value.latitude, entry.value.longitude),
        isSelf: entry.key == selfId,
        headingDegrees: entry.value.headingDegrees,
        ordinal: standings[entry.key]?.ordinal ?? 0,
        tier: standings[entry.key]?.tier ?? GapTier.green,
      ),
  ];
});

/// Viewport that auto-fits all current convoy member positions.
/// Falls back to a default city-centre view when no members are tracked.
final liveViewportProvider = Provider.autoDispose<MapViewport>((ref) {
  final markers = ref.watch(memberMarkersProvider);
  return MapViewport.fitPositions([
    for (final m in markers)
      (lat: m.position.latitude, lng: m.position.longitude),
  ]);
});

/// Holds the OSRM road route for the current tour and refetches it whenever the
/// tour changes (≥2 stops). Keeps the previous [RoadRoute] while a refetch is in
/// flight so the drawn line does not flicker, and clears it once the tour drops
/// below 2 stops. Returns `null` until the first route resolves (or on failure),
/// which is the UI's cue to fall back to the straight-line overlay.
class RoadRouteNotifier extends StateNotifier<RoadRoute?> {
  RoadRouteNotifier(this._service, WaypointTour tour) : super(null) {
    fetchFor(tour);
  }

  final RoadRouteService _service;
  int _requestId = 0;

  Future<void> fetchFor(WaypointTour tour) async {
    if (tour.length < RoadRouteService.minWaypoints) {
      _requestId++; // invalidate any in-flight fetch
      state = null;
      return;
    }
    final id = ++_requestId;
    final route = await _service.fetch(tour.stops);
    if (id != _requestId) return; // a newer tour superseded this fetch
    // Keep the previous line on a failed fetch instead of blanking the route.
    if (route != null) state = route;
  }
}

/// Road route for the active tour. Watches [tourProvider]; an unchanged tour
/// (same value) does not retrigger a fetch because the listener only fires on a
/// distinct [WaypointTour]. Override [roadRouteServiceProvider] in tests.
final roadRouteProvider =
    StateNotifierProvider.autoDispose<RoadRouteNotifier, RoadRoute?>((ref) {
  final service = ref.watch(roadRouteServiceProvider);
  final notifier = RoadRouteNotifier(service, ref.read(tourProvider));
  ref.listen(tourProvider, (_, next) => notifier.fetchFor(next));
  return notifier;
});
