import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/convoy.dart';
import '../domain/proximity_warning.dart';
import 'convoy_providers.dart';

/// Wie lange ein Abstands-Banner sichtbar bleibt, bevor es sich selbst
/// ausblendet. Die Warnungen sind event-getrieben (Member kam zu nah) — ohne
/// TTL bliebe der letzte Event-Zustand für immer stehen.
const kProximityWarningTtl = Duration(seconds: 30);

/// Maximale Länge der UID-Kurzform, wenn ein Member (noch) nicht im Roster
/// steht und daher kein Anzeigename bekannt ist.
const kMemberIdShortLength = 8;

/// Anzeigename eines Members aus dem Konvoi-Roster — Fallback ist die
/// gekürzte rohe Member-ID (Firebase-UIDs sind 28 Zeichen und unlesbar).
String memberDisplayName(Convoy? convoy, String memberId) {
  final name = convoy?.members
      .where((m) => m.id == memberId)
      .firstOrNull
      ?.displayName;
  if (name != null && name.trim().isNotEmpty) return name;
  if (memberId.length <= kMemberIdShortLength) return memberId;
  return '${memberId.substring(0, kMemberIdShortLength)}…';
}

/// Hält die jüngste [ProximityWarning] und räumt sie nach
/// [kProximityWarningTtl] automatisch weg. Jede neue Warnung setzt den Timer
/// zurück. Konsumiert von `ProximityBanner` und der Driver-Proximity-Card.
final activeProximityWarningProvider = NotifierProvider.autoDispose<
    ActiveProximityWarningNotifier, ProximityWarning?>(
  ActiveProximityWarningNotifier.new,
);

class ActiveProximityWarningNotifier
    extends AutoDisposeNotifier<ProximityWarning?> {
  Timer? _clearTimer;

  @override
  ProximityWarning? build() {
    ref.listen(proximityWarningsProvider, (_, next) {
      final warning = next.valueOrNull;
      if (warning == null) return;
      state = warning;
      _restartClearTimer();
    });
    ref.onDispose(() => _clearTimer?.cancel());
    return null;
  }

  void _restartClearTimer() {
    _clearTimer?.cancel();
    _clearTimer = Timer(kProximityWarningTtl, () => state = null);
  }
}
