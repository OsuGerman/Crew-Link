import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/hazard_report.dart';
import '../../../core/realtime/hazard_event.dart';
import 'convoy_providers.dart';

/// Standard-TTL für eine Gefahrenmeldung. Bewusst kurz — Verkehrslage
/// ändert sich schnell, abgelaufene Pins wären schlimmer als gar keine.
const Duration kHazardDefaultTtl = Duration(minutes: 30);

/// Notifier mit allen aktiven Hazards des laufenden Konvois. Sync läuft
/// über den WebSocket-Channel (Wire-Type `hazard` für neue, `hazard_remove`
/// für Entfernen). Abgelaufene Hazards werden lokal automatisch gefiltert.
class HazardPingsNotifier extends StateNotifier<List<HazardReport>> {
  HazardPingsNotifier(this._ref) : super(const []) {
    _bindToSocket();
    _ref.listen(convoySocketProvider, (_, __) => _bindToSocket());
    // Alle 30 Sekunden abgelaufene Hazards aus dem State filtern. Das ist
    // grob genug für UI-Updates und vermeidet ein Per-Sekunden-Rebuild.
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pruneExpired(),
    );
  }

  final Ref _ref;
  StreamSubscription<HazardEvent>? _socketSub;
  Timer? _pruneTimer;

  void _bindToSocket() {
    _socketSub?.cancel();
    final socket = _ref.read(convoySocketProvider);
    if (socket == null) {
      state = const [];
      return;
    }
    _socketSub = socket.hazardEvents.listen((event) {
      switch (event) {
        case HazardAdded(:final report):
          // Replace if same id already present (idempotent for re-broadcasts).
          state = [
            for (final h in state)
              if (h.id != report.id) h,
            report,
          ];
        case HazardRemoved(:final id):
          state = [for (final h in state) if (h.id != id) h];
      }
    });
  }

  /// Pushes a new hazard to all members. `setBy` ist die eigene
  /// Member-ID; der Server validiert das gegen den authenticated sender.
  void report({
    required HazardType type,
    required double latitude,
    required double longitude,
    required String reporterId,
    required String convoyId,
    String? description,
    Duration ttl = kHazardDefaultTtl,
  }) {
    final now = DateTime.now().toUtc();
    final report = HazardReport(
      id: 'draft-${now.microsecondsSinceEpoch}-$reporterId',
      type: type,
      latitude: latitude,
      longitude: longitude,
      reporterId: reporterId,
      convoyId: convoyId,
      createdAt: now,
      expiresAt: now.add(ttl),
      description: description,
    );
    // Optimistic local apply — UI feedback in <1 frame.
    state = [...state, report];
    _ref.read(convoySocketProvider)?.publishHazardReport(report);
  }

  /// Removes a hazard locally and broadcasts the removal.
  /// Nur der Reporter kann seinen eigenen Hazard löschen (server enforced).
  void remove(String hazardId) {
    state = [for (final h in state) if (h.id != hazardId) h];
    _ref.read(convoySocketProvider)?.publishHazardRemoval(hazardId);
  }

  void _pruneExpired() {
    final now = DateTime.now().toUtc();
    final fresh = state.where((h) => h.isActiveAt(now)).toList();
    if (fresh.length != state.length) state = fresh;
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _pruneTimer?.cancel();
    super.dispose();
  }
}

final hazardPingsProvider =
    StateNotifierProvider<HazardPingsNotifier, List<HazardReport>>(
  (ref) => HazardPingsNotifier(ref),
);
