/// Fired when a member has been continuously beyond the proximity threshold
/// for at least [kSustainedSeconds]. Distinct from [ProximityWarning], which
/// fires on every threshold crossing — a split indicates a sustained separation.
class ConvoySplitEvent {
  const ConvoySplitEvent({
    required this.splitMemberId,
    required this.distanceMeters,
    required this.detectedAt,
  });

  /// Seconds a member must remain beyond the proximity threshold before a
  /// split is declared. Chosen to filter brief GPS jitter or overtaking.
  static const int kSustainedSeconds = 30;

  final String splitMemberId;
  final double distanceMeters;
  final DateTime detectedAt;
}
