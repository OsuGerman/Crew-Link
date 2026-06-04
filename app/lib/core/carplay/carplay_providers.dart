import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/convoy/application/convoy_providers.dart';
import '../../features/push_to_talk/application/ptt_providers.dart';
import 'carplay_bridge.dart';

/// Singleton CarPlay bridge — one instance per app lifetime.
/// On non-iOS platforms the native side never sends events, so this is
/// safe to instantiate unconditionally.
final carPlayBridgeProvider = Provider<CarPlayBridge>((ref) {
  final bridge = CarPlayBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});

/// Registers the CarPlay PTT-button handler eagerly at app start (watched in
/// `CrewLinkApp`), not only inside the active-convoy screen — otherwise a
/// button press before a convoy is open is lost (no handler registered yet).
///
/// [pttStateProvider] is read lazily inside the event callback: merely watching
/// this provider must not instantiate the PTT stack (whose notifier subscribes
/// to the native audio-session channel), which would throw on web / in tests.
final carPlayPttWiringProvider = Provider<void>((ref) {
  if (kIsWeb) return;
  final bridge = ref.watch(carPlayBridgeProvider);
  final sub = bridge.events.listen((event) {
    final notifier = ref.read(pttStateProvider.notifier);
    if (event == const CarPlayEvent.pttPressed()) {
      unawaited(notifier.startTransmitting());
    } else if (event == const CarPlayEvent.pttReleased()) {
      unawaited(notifier.stopTransmitting());
    }
  });
  ref.onDispose(sub.cancel);
});

/// Pushes the active convoy's member count and proximity-warning state to the
/// CarPlay map-template header whenever either changes. Watch from the active-
/// convoy screen — the state is only meaningful while a convoy is open.
final carPlayConvoyStateWiringProvider = Provider<void>((ref) {
  if (kIsWeb) return;
  final bridge = ref.watch(carPlayBridgeProvider);

  void push() {
    final convoy = ref.read(currentConvoyProvider);
    if (convoy == null) return;
    final hasWarning = ref.read(proximityWarningsProvider).valueOrNull != null;
    unawaited(bridge.updateConvoyState(
      memberCount: convoy.members.length,
      proximityActive: hasWarning,
    ));
  }

  ref.listen(currentConvoyProvider, (_, __) => push());
  ref.listen(proximityWarningsProvider, (_, __) => push());
  push();
});
