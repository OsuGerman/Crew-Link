/// Emitted when another convoy member crosses the configured proximity
/// threshold relative to the local member.
class ProximityWarning {
  const ProximityWarning({
    required this.otherMemberId,
    required this.distanceMeters,
    required this.thresholdMeters,
    required this.triggeredAt,
  });

  final String otherMemberId;
  final double distanceMeters;
  final double thresholdMeters;
  final DateTime triggeredAt;

  @override
  String toString() =>
      'ProximityWarning(other=$otherMemberId, '
      'distance=${distanceMeters.toStringAsFixed(1)}m, '
      'threshold=${thresholdMeters.toStringAsFixed(0)}m)';
}
