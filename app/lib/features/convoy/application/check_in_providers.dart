import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/waypoint_check_in.dart';
import 'convoy_providers.dart';
import 'waypoint_providers.dart';

/// Notifier für alle eingegangenen Stopp-Bestätigungen im aktuellen Konvoi.
///
/// State ist ein `Set<WaypointCheckIn>` — Identität via `(memberId, stopSig)`
/// (siehe `WaypointCheckIn.==`), idempotent gegen Re-Broadcast.
///
/// Wird automatisch geleert wenn die Tour vorrückt: sobald sich der Head
/// ändert, sind die Check-Ins für den alten Head irrelevant. Wir filtern
/// also kontinuierlich auf "Check-Ins für aktuellen Head"; die UI
/// (Banner, Sheet) liest daraus.
class CheckInsNotifier extends StateNotifier<Set<WaypointCheckIn>> {
  CheckInsNotifier(this._ref) : super(const <WaypointCheckIn>{}) {
    _bindToSocket();
    _ref.listen(convoySocketProvider, (_, __) => _bindToSocket());
  }

  final Ref _ref;
  StreamSubscription<WaypointCheckIn>? _socketSub;

  void _bindToSocket() {
    _socketSub?.cancel();
    final socket = _ref.read(convoySocketProvider);
    if (socket == null) {
      state = const <WaypointCheckIn>{};
      return;
    }
    _socketSub = socket.checkIns.listen((checkIn) {
      state = {...state, checkIn};
    });
  }

  /// Manuell „Bin da" senden — fügt lokal hinzu und broadcastet.
  void checkInAtCurrentStop(String selfMemberId) {
    final tour = _ref.read(tourProvider);
    final current = tour.current;
    if (current == null) return;
    final ci = WaypointCheckIn(
      memberId: selfMemberId,
      stopSignature: WaypointCheckIn.signatureOf(current),
      arrivedAt: DateTime.now().toUtc(),
    );
    state = {...state, ci};
    _ref.read(convoySocketProvider)?.publishCheckIn(ci);
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }
}

final checkInsProvider = StateNotifierProvider<CheckInsNotifier,
    Set<WaypointCheckIn>>((ref) => CheckInsNotifier(ref));

/// Check-Ins gefiltert auf den aktuellen Tour-Head — was den User wirklich
/// interessiert ("wer ist am NÄCHSTEN Stopp angekommen").
final currentStopCheckInsProvider =
    Provider<List<WaypointCheckIn>>((ref) {
  final tour = ref.watch(tourProvider);
  final current = tour.current;
  if (current == null) return const [];
  final sig = WaypointCheckIn.signatureOf(current);
  final all = ref.watch(checkInsProvider);
  return all.where((c) => c.stopSignature == sig).toList();
});

/// True wenn der lokale User am aktuellen Stopp eingecheckt hat.
final selfHasCheckedInProvider = Provider<bool>((ref) {
  final selfId = ref.watch(selfMemberIdProvider);
  return ref
      .watch(currentStopCheckInsProvider)
      .any((c) => c.memberId == selfId);
});
