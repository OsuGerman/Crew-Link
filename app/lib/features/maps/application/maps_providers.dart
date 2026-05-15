import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/gps_update.dart';
import '../../convoy/application/convoy_providers.dart';
import '../domain/map_viewport.dart';

typedef MemberMarker = ({
  String memberId,
  LatLng position,
  bool isSelf,
  double headingDegrees,
});

/// Live list of map markers derived from the active convoy session.
/// Each entry carries the member id, its current LatLng, heading, and whether
/// it represents the local user (rendered differently on the map).
final memberMarkersProvider = Provider.autoDispose<List<MemberMarker>>((ref) {
  final Map<String, GpsUpdate> positions =
      ref.watch(livePositionsProvider).valueOrNull ?? const <String, GpsUpdate>{};
  final selfId = ref.watch(selfMemberIdProvider);
  return [
    for (final entry in positions.entries)
      (
        memberId: entry.key,
        position: LatLng(entry.value.latitude, entry.value.longitude),
        isSelf: entry.key == selfId,
        headingDegrees: entry.value.headingDegrees,
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
