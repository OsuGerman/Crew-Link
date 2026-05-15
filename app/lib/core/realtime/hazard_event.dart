import '../models/hazard_report.dart';

/// Sealed event-type emitted by the convoy WebSocket for hazard-pin
/// life-cycle: a new pin is added, or an existing pin is removed by
/// its reporter / expires server-side.
sealed class HazardEvent {
  const HazardEvent();
}

final class HazardAdded extends HazardEvent {
  const HazardAdded(this.report);
  final HazardReport report;
}

final class HazardRemoved extends HazardEvent {
  const HazardRemoved(this.id);
  final String id;
}
