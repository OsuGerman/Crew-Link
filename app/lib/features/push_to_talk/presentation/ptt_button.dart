import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ptt_providers.dart';

/// Hold-down push-to-talk button.
///
/// Pointer-level events (Listener) are used instead of GestureDetector so
/// that the recording starts on the very first frame of contact and stops the
/// moment the finger lifts — no tap-delay, no gesture-arena ambiguity.
class PttButton extends ConsumerWidget {
  const PttButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(pttActiveProvider);
    return Listener(
      onPointerDown: (_) =>
          ref.read(pttStateProvider.notifier).startTransmitting(),
      onPointerUp: (_) =>
          ref.read(pttStateProvider.notifier).stopTransmitting(),
      onPointerCancel: (_) =>
          ref.read(pttStateProvider.notifier).stopTransmitting(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.red : Colors.blueGrey,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 4,
                  ),
                ]
              : null,
        ),
        child: const Icon(Icons.mic, color: Colors.white, size: 32),
      ),
    );
  }
}
