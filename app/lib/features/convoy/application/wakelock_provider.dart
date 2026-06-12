import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';
import 'convoy_providers.dart';

/// Schmale Wakelock-Abstraktion, damit Tests nicht das echte
/// wakelock_plus-Plugin (Platform-Channel) brauchen — Fake injizieren via
/// [wakelockControlProvider].
abstract class WakelockControl {
  Future<void> enable();
  Future<void> disable();
}

class _PluginWakelockControl implements WakelockControl {
  const _PluginWakelockControl();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

/// Default-Implementierung: wakelock_plus. In Widget-/Unit-Tests
/// überschreiben (siehe `test/support/active_view_test_overrides.dart`).
final wakelockControlProvider =
    Provider<WakelockControl>((ref) => const _PluginWakelockControl());

/// Hält das Display wach, solange ein Konvoi aktiv ist — während der Fahrt
/// darf der Screen mit der Live-Karte nicht in den Lockscreen fallen.
///
/// Muster wie [lostConnectionWatcherProvider]: Seiteneffekt-Provider, der im
/// Active-View-Widget-Tree per `ref.watch` aktiviert wird. Beim Verlassen des
/// Konvois (oder Unmount der View → autoDispose) wird der Wakelock wieder
/// freigegeben.
final convoyWakelockProvider = Provider.autoDispose<void>((ref) {
  final control = ref.watch(wakelockControlProvider);
  final inConvoy = ref.watch(currentConvoyProvider.select((c) => c != null));

  Future<void> apply(bool keepAwake) async {
    try {
      if (keepAwake) {
        await control.enable();
      } else {
        await control.disable();
      }
    } catch (e, st) {
      appLog.e('ConvoyWakelock', error: e, stackTrace: st);
      unawaited(ObservabilityBootstrap.build().reportError(e, st));
    }
  }

  unawaited(apply(inConvoy));
  ref.onDispose(() => unawaited(apply(false)));
});
