import '../../core/models/gps_update.dart';
import 'geo_distance.dart';

/// One unique member pairing and the Haversine distance between them.
class DistancePairing {
  const DistancePairing({
    required this.memberAId,
    required this.memberBId,
    required this.distanceMeters,
  });

  final String memberAId;
  final String memberBId;
  final double distanceMeters;

  @override
  String toString() =>
      'DistancePairing($memberAId↔$memberBId, '
      '${distanceMeters.toStringAsFixed(0)} m)';
}

/// Pure, stateless engine that evaluates every unique member pairing in a
/// positions snapshot and returns those whose Haversine distance exceeds
/// [thresholdMeters] (default 500 m per project spec).
///
/// All n*(n-1)/2 pairs are checked — not just self-vs-others — so the
/// engine can power both local warnings and the RTDB breach-broadcast that
/// notifies members about remote separations they cannot compute themselves.
///
/// Members within [thresholdMeters] are silently omitted; callers receive
/// only the breached pairs and can act on them without extra filtering.
class DistanceEngine {
  const DistanceEngine({this.thresholdMeters = 500.0});

  final double thresholdMeters;

  /// Returns all unique pairs from [positions] whose distance exceeds
  /// [thresholdMeters]. Returns an empty list when fewer than 2 members
  /// are present or no pair breaches the threshold.
  List<DistancePairing> evaluate(Map<String, GpsUpdate> positions) {
    final ids = positions.keys.toList();
    if (ids.length < 2) return const [];

    final result = <DistancePairing>[];
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = positions[ids[i]]!;
        final b = positions[ids[j]]!;
        final dist = haversineMeters(
          lat1: a.latitude,
          lon1: a.longitude,
          lat2: b.latitude,
          lon2: b.longitude,
        );
        if (dist > thresholdMeters) {
          result.add(DistancePairing(
            memberAId: ids[i],
            memberBId: ids[j],
            distanceMeters: dist,
          ));
        }
      }
    }
    return result;
  }
}
