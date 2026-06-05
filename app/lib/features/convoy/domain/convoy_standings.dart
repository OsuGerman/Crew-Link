import '../../../core/geo/geo_distance.dart';
import '../../../core/models/convoy_member.dart';
import '../../../core/models/gps_update.dart';

/// Gap status of a convoy member relative to the configured warning threshold.
enum GapTier { green, yellow, red }

/// A member's live standing in the convoy: their ordinal position (#1 = leader /
/// front) and their gap tier behind the leader.
class MemberStanding {
  const MemberStanding({
    required this.ordinal,
    required this.tier,
    this.gapMeters,
  });

  /// 1-based position; #1 is the leader (or the front-most live member).
  final int ordinal;

  /// Green/yellow/red bucket of [gapMeters] vs the threshold.
  final GapTier tier;

  /// Distance behind the leader in metres; null for the leader itself or when
  /// the leader has no live position.
  final double? gapMeters;
}

/// Ranks every member that has a live position by distance from the convoy
/// leader and buckets each into a green/yellow/red gap tier vs
/// [thresholdMeters]: green < 50% of threshold, yellow < threshold, red ≥
/// threshold. The leader is always #1 and green. Members without a position
/// get no standing.
Map<String, MemberStanding> computeConvoyStandings({
  required List<ConvoyMember> members,
  required Map<String, GpsUpdate> positions,
  required double thresholdMeters,
}) {
  String? leaderId;
  for (final m in members) {
    if (m.isLeader) {
      leaderId = m.id;
      break;
    }
  }
  final leaderPos = leaderId == null ? null : positions[leaderId];

  double? gapOf(String id) {
    if (leaderPos == null || id == leaderId) return null;
    final p = positions[id];
    if (p == null) return null;
    return haversineMeters(
      lat1: leaderPos.latitude,
      lon1: leaderPos.longitude,
      lat2: p.latitude,
      lon2: p.longitude,
    );
  }

  final ids = positions.keys.toList()
    ..sort((a, b) {
      if (a == leaderId) return -1;
      if (b == leaderId) return 1;
      final ga = gapOf(a) ?? double.infinity;
      final gb = gapOf(b) ?? double.infinity;
      final cmp = ga.compareTo(gb);
      return cmp != 0 ? cmp : a.compareTo(b);
    });

  GapTier tierOf(String id, double? gap) {
    if (id == leaderId || gap == null) return GapTier.green;
    if (gap < thresholdMeters * 0.5) return GapTier.green;
    if (gap < thresholdMeters) return GapTier.yellow;
    return GapTier.red;
  }

  final standings = <String, MemberStanding>{};
  for (var i = 0; i < ids.length; i++) {
    final id = ids[i];
    final gap = gapOf(id);
    standings[id] = MemberStanding(
      ordinal: i + 1,
      tier: tierOf(id, gap),
      gapMeters: gap,
    );
  }
  return standings;
}
