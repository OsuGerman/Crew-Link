import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/geo_distance.dart';
import '../domain/waypoint.dart';
import '../domain/waypoint_tour.dart';
import 'convoy_providers.dart';

/// Routen-Plan (geordnete Stopp-Liste) für den aktiven Konvoi.
///
/// Sync läuft bidirektional über den WebSocket-Channel:
///   • Inbound  `{type:'tour', payload:{stops:[...]}}` schreibt den State
///     ohne Re-Publish (kein Echo-Storm).
///   • Outbound: jede Mutation via `addStop()`, `removeAt()`, `reorder()`,
///     `advance()`, `clear()` publisht den kompletten neuen Plan.
class TourNotifier extends StateNotifier<WaypointTour> {
  TourNotifier(this._ref) : super(WaypointTour.empty) {
    _bindToSocket();
    _ref.listen(convoySocketProvider, (_, __) => _bindToSocket());
  }

  final Ref _ref;
  StreamSubscription<WaypointTour>? _socketSub;

  void _bindToSocket() {
    _socketSub?.cancel();
    final socket = _ref.read(convoySocketProvider);
    if (socket == null) {
      state = WaypointTour.empty;
      return;
    }
    _socketSub = socket.tourUpdates.listen((tour) {
      state = tour;
    });
  }

  void _push(WaypointTour next) {
    state = next;
    _ref.read(convoySocketProvider)?.publishTour(next);
  }

  void addStop(Waypoint waypoint) => _push(state.add(waypoint));

  void removeAt(int index) => _push(state.removeAt(index));

  void reorder(int oldIndex, int newIndex) =>
      _push(state.reorder(oldIndex, newIndex));

  /// Stop erreicht — entfernt den ersten Eintrag und schiebt den Plan vor.
  void advance() => _push(state.advance());

  void clear() => _push(WaypointTour.empty);

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }
}

final tourProvider =
    StateNotifierProvider<TourNotifier, WaypointTour>(
  (ref) => TourNotifier(ref),
);

/// Aktueller Stopp (= erstes Element der Tour) als bequemer Shortcut.
/// Banner + Distance/Bearing leiten sich davon ab.
final currentStopProvider = Provider<Waypoint?>((ref) {
  return ref.watch(tourProvider).current;
});

/// `true` wenn der lokale User Leader des aktiven Konvois ist.
final selfIsLeaderProvider = Provider<bool>((ref) {
  final convoy = ref.watch(currentConvoyProvider);
  if (convoy == null) return false;
  final selfId = ref.watch(selfMemberIdProvider);
  return convoy.members.any((m) => m.id == selfId && m.isLeader);
});

/// Distanz in Metern von der eigenen Position zum aktuellen Stopp.
final waypointDistanceMetersProvider = Provider<double?>((ref) {
  final wp = ref.watch(currentStopProvider);
  if (wp == null) return null;
  final selfId = ref.watch(selfMemberIdProvider);
  final positions = ref.watch(livePositionsProvider).valueOrNull;
  final self = positions?[selfId];
  if (self == null) return null;
  return haversineMeters(
    lat1: self.latitude,
    lon1: self.longitude,
    lat2: wp.latitude,
    lon2: wp.longitude,
  );
});

/// Peilung in Grad (0° = Nord) von der eigenen Position zum Stopp.
final waypointBearingDegreesProvider = Provider<double?>((ref) {
  final wp = ref.watch(currentStopProvider);
  if (wp == null) return null;
  final selfId = ref.watch(selfMemberIdProvider);
  final positions = ref.watch(livePositionsProvider).valueOrNull;
  final self = positions?[selfId];
  if (self == null) return null;
  return bearingDegrees(
    lat1: self.latitude,
    lon1: self.longitude,
    lat2: wp.latitude,
    lon2: wp.longitude,
  );
});

/// Backward-Compat-Alias damit existierende Banner-Widgets keinen Rename
/// brauchen. Zeigt den ersten Stopp; eine spätere Iteration kann diesen
/// alias entfernen wenn alle Konsumenten direkt auf `currentStopProvider`
/// migriert sind.
final waypointProvider = currentStopProvider;
