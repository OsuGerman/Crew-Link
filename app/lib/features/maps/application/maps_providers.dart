import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/gps_update.dart';
import '../../convoy/application/convoy_providers.dart';
import '../../convoy/domain/convoy_standings.dart';
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

/// Whether the active convoy view shows the live street map (true) or the
/// proximity radar (false). User-toggleable; defaults to the map. Widget tests
/// override this to false so they don't instantiate the native MapLibre view.
final mapViewEnabledProvider = StateProvider<bool>((ref) => true);

/// Viewport that auto-fits all current convoy member positions.
/// Falls back to a default city-centre view when no members are tracked.
final liveViewportProvider = Provider.autoDispose<MapViewport>((ref) {
  final markers = ref.watch(memberMarkersProvider);
  return MapViewport.fitPositions([
    for (final m in markers)
      (lat: m.position.latitude, lng: m.position.longitude),
  ]);
});
