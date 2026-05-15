import 'package:flutter/foundation.dart';

import 'waypoint.dart';

/// Geordnete Liste von Navigationspunkten — der "Plan" für den Konvoi.
/// `stops[0]` ist der aktuell aktive Stopp (Banner zeigt diesen).
/// Wird komplett-state-synchronisiert über den Konvoi-WebSocket
/// (`{type:'tour', payload:{stops:[…]}}`); keine inkrementellen Events.
@immutable
class WaypointTour {
  const WaypointTour({this.stops = const <Waypoint>[]});

  factory WaypointTour.fromJson(Map<String, Object?> json) {
    final raw = json['stops'] as List<Object?>? ?? const <Object?>[];
    return WaypointTour(
      stops: raw
          .map((e) => Waypoint.fromJson((e! as Map).cast<String, Object?>()))
          .toList(growable: false),
    );
  }

  static const WaypointTour empty = WaypointTour();

  final List<Waypoint> stops;

  bool get isEmpty => stops.isEmpty;
  bool get isNotEmpty => stops.isNotEmpty;
  int get length => stops.length;

  /// Aktuell aktiver Stopp (Banner-Target). `null` wenn Tour leer.
  Waypoint? get current => stops.isEmpty ? null : stops.first;

  WaypointTour copyWith({List<Waypoint>? stops}) =>
      WaypointTour(stops: stops ?? this.stops);

  WaypointTour add(Waypoint wp) =>
      WaypointTour(stops: [...stops, wp]);

  WaypointTour removeAt(int index) {
    if (index < 0 || index >= stops.length) return this;
    return WaypointTour(stops: [
      for (var i = 0; i < stops.length; i++)
        if (i != index) stops[i],
    ]);
  }

  /// Markiert den aktuellen Stopp als erreicht und schiebt den Plan vor.
  /// Liefert die leere Tour wenn keine Stopps übrig sind.
  WaypointTour advance() {
    if (stops.isEmpty) return this;
    return WaypointTour(stops: stops.sublist(1));
  }

  WaypointTour reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return this;
    if (oldIndex < 0 || oldIndex >= stops.length) return this;
    final list = [...stops];
    final item = list.removeAt(oldIndex);
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    list.insert(adjusted.clamp(0, list.length), item);
    return WaypointTour(stops: list);
  }

  Map<String, Object?> toJson() => {
        'stops': stops.map((s) => s.toJson()).toList(growable: false),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaypointTour &&
          stops.length == other.stops.length &&
          List.generate(stops.length, (i) => stops[i] == other.stops[i])
              .every((b) => b);

  @override
  int get hashCode => Object.hashAll(stops);
}
