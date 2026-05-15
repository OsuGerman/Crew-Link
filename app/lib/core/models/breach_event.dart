/// Snapshot of a distance-breach between two convoy members, broadcast via
/// Firebase RTDB so every device in the convoy can show a local notification.
///
/// [memberAId] and [memberBId] are always stored in ascending lexicographic
/// order — use [pairKey] to derive the RTDB path key so both sides of the
/// breach land on the same entry (last-write-wins deduplication).
class BreachEvent {
  const BreachEvent({
    required this.id,
    required this.convoyId,
    required this.memberAId,
    required this.memberBId,
    required this.distanceMeters,
    required this.triggeredAt,
  });

  factory BreachEvent.fromRtdb(
    String id,
    String convoyId,
    Map<String, Object?> data,
  ) {
    return BreachEvent(
      id: id,
      convoyId: convoyId,
      memberAId: data['memberAId']! as String,
      memberBId: data['memberBId']! as String,
      distanceMeters: (data['distanceMeters']! as num).toDouble(),
      triggeredAt: DateTime.parse(data['triggeredAt']! as String),
    );
  }

  /// RTDB key that is identical regardless of which device writes first.
  static String pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '${a}__$b' : '${b}__$a';

  final String id;
  final String convoyId;
  final String memberAId;
  final String memberBId;
  final double distanceMeters;
  final DateTime triggeredAt;

  Map<String, Object?> toRtdb() => {
        'memberAId': memberAId,
        'memberBId': memberBId,
        'distanceMeters': distanceMeters,
        'triggeredAt': triggeredAt.toUtc().toIso8601String(),
      };
}
