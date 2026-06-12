import 'dart:async';
import 'dart:convert';

import '../../features/convoy/domain/quick_action.dart';
import '../../features/convoy/domain/waypoint.dart';
import '../../features/convoy/domain/waypoint_check_in.dart';
import '../../features/convoy/domain/waypoint_tour.dart';
import '../models/gps_update.dart';
import '../models/hazard_report.dart';
import '../observability/app_logger.dart';
import '../observability/observability_bootstrap.dart';
import 'hazard_event.dart';

/// Dekodiertes Inbound-Wire-Frame des Konvoi-WebSockets. Eine Variante pro
/// Wire-Type; unbekannte oder kaputte Frames werden zu `null` dekodiert und
/// vom Client ignoriert (forward-kompatibel mit neuen Server-Frame-Typen).
sealed class InboundFrame {
  const InboundFrame();
}

class GpsFrame extends InboundFrame {
  const GpsFrame(this.update);
  final GpsUpdate update;
}

class WaypointFrame extends InboundFrame {
  const WaypointFrame(this.waypoint);

  /// `null` = Leader hat den Waypoint gelöscht.
  final Waypoint? waypoint;
}

class HazardFrame extends InboundFrame {
  const HazardFrame(this.event);
  final HazardEvent event;
}

class TourFrame extends InboundFrame {
  const TourFrame(this.tour);
  final WaypointTour tour;
}

class CheckInFrame extends InboundFrame {
  const CheckInFrame(this.checkIn);
  final WaypointCheckIn checkIn;
}

class QuickActionFrame extends InboundFrame {
  const QuickActionFrame(this.action);
  final QuickAction action;
}

/// Dekodiert einen rohen WebSocket-Frame in ein [InboundFrame].
/// Liefert `null` für Nicht-String-Frames, malformed JSON, unbekannte
/// Frame-Typen und Payloads in unerwarteter Form.
InboundFrame? decodeInboundFrame(dynamic frame) {
  if (frame is! String) return null;
  final dynamic decoded;
  try {
    decoded = jsonDecode(frame);
  } catch (error, stack) {
    // Malformed Server-Frame darf den Stream-Listener nicht crashen.
    appLog.e('ConvoySocket: malformed inbound frame',
        error: error, stackTrace: stack);
    unawaited(ObservabilityBootstrap.build().reportError(error, stack));
    return null;
  }
  if (decoded is! Map) return null;
  final raw = decoded['payload'];
  switch (decoded['type']) {
    case 'gps':
      if (raw is! Map) return null;
      return GpsFrame(GpsUpdate.fromJson(raw.cast<String, Object?>()));
    case 'waypoint':
      if (raw == null) return const WaypointFrame(null);
      if (raw is! Map) return null;
      return WaypointFrame(Waypoint.fromJson(raw.cast<String, Object?>()));
    case 'hazard':
      if (raw is! Map) return null;
      return HazardFrame(
        HazardAdded(HazardReport.fromJson(raw.cast<String, Object?>())),
      );
    case 'hazard_remove':
      if (raw is! Map || raw['id'] is! String) return null;
      return HazardFrame(HazardRemoved(raw['id'] as String));
    case 'tour':
      if (raw is! Map) return null;
      return TourFrame(WaypointTour.fromJson(raw.cast<String, Object?>()));
    case 'checkin':
      if (raw is! Map) return null;
      return CheckInFrame(
        WaypointCheckIn.fromJson(raw.cast<String, Object?>()),
      );
    case 'status':
      if (raw is! Map) return null;
      return QuickActionFrame(
        QuickAction.fromJson(raw.cast<String, Object?>()),
      );
    default:
      return null;
  }
}
