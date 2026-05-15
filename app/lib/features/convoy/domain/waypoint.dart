import 'package:flutter/foundation.dart';

/// Vom Konvoi-Leader gesetzter Navigationspunkt — Ziel für alle Mitglieder.
///
/// Wird im aktiven Konvoi als Banner oberhalb des Radars angezeigt
/// (Distanz + Kompassrichtung). Sync zwischen Mitgliedern läuft über das
/// bestehende WebSocket pro Konvoi-Channel (Wire-Type `waypoint`); siehe
/// `core/realtime/convoy_socket_client.dart`.
@immutable
class Waypoint {
  const Waypoint({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.setBy,
    required this.setAt,
  });

  /// JSON-Wire-Format. `setAt` als ISO8601-UTC.
  factory Waypoint.fromJson(Map<String, Object?> json) => Waypoint(
        latitude: (json['latitude']! as num).toDouble(),
        longitude: (json['longitude']! as num).toDouble(),
        label: json['label']! as String,
        setBy: json['setBy']! as String,
        setAt: DateTime.parse(json['setAt']! as String),
      );

  final double latitude;
  final double longitude;
  final String label;
  final String setBy;
  final DateTime setAt;

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'label': label,
        'setBy': setBy,
        'setAt': setAt.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Waypoint &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          label == other.label &&
          setBy == other.setBy &&
          setAt == other.setAt;

  @override
  int get hashCode => Object.hash(latitude, longitude, label, setBy, setAt);
}
