import 'package:flutter/foundation.dart';

import 'waypoint.dart';

/// Bestätigung eines Mitglieds dass es einen Tour-Stopp erreicht hat.
///
/// Identifiziert den konkreten Stopp via `stopSignature` (kombiniert
/// setBy + setAt), damit Check-Ins nur für den Stopp gelten der gerade
/// das aktuelle Ziel ist. Sobald die Tour vorrückt (advance() entfernt
/// Head), werden Check-Ins für den alten Head automatisch irrelevant.
@immutable
class WaypointCheckIn {
  const WaypointCheckIn({
    required this.memberId,
    required this.stopSignature,
    required this.arrivedAt,
  });

  factory WaypointCheckIn.fromJson(Map<String, Object?> json) =>
      WaypointCheckIn(
        memberId: json['memberId']! as String,
        stopSignature: json['stopSignature']! as String,
        arrivedAt: DateTime.parse(json['arrivedAt']! as String),
      );

  /// Stabile ID für einen Stopp aus seinen unveränderlichen Feldern.
  /// Two-stops-mit-gleichem-setBy-im-gleichen-Mikrosekunden sind
  /// physikalisch ausgeschlossen → reicht als Collision-Free-Signatur.
  static String signatureOf(Waypoint stop) =>
      '${stop.setBy}|${stop.setAt.toUtc().toIso8601String()}';

  final String memberId;
  final String stopSignature;
  final DateTime arrivedAt;

  Map<String, Object?> toJson() => {
        'memberId': memberId,
        'stopSignature': stopSignature,
        'arrivedAt': arrivedAt.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaypointCheckIn &&
          memberId == other.memberId &&
          stopSignature == other.stopSignature;

  @override
  int get hashCode => Object.hash(memberId, stopSignature);
}
