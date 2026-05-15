import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Wires CarPlay PTT-button events to [PttStateNotifier].
/// Watch from the active convoy screen so the subscription lives only
/// while a convoy session is open.
final carPlayPttWiringProvider = Provider<void>((ref) {
  if (kIsWeb) return;
  final bridge = ref.watch(carPlayBridgeProvider);
  final notifier = ref.read(pttStateProvider.notifier);
  final sub = bridge.events.listen((event) {
    if (event == const CarPlayEvent.pttPressed()) {
      unawaited(notifier.startTransmitting());
    } else if (event == const CarPlayEvent.pttReleased()) {
      unawaited(notifier.stopTransmitting());
    }
  });
  ref.onDispose(sub.cancel);
});
