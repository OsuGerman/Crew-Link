import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/ptt_providers.dart';

/// Hold-down Push-to-Talk-Button — Theme-konform mit Orange-Akzent.
///
/// Pointer-Events statt GestureDetector damit Recording mit dem allerersten
/// Frame des Kontakts startet (kein Tap-Delay, keine Gesture-Arena).
/// Idle nur ein dezenter Schein; erst während Transmission wird der rote
/// Glow deutlich — Glow ist hier Zustandssignal, kein Dauer-Deko-Effekt.
class PttButton extends ConsumerWidget {
  const PttButton({super.key, this.size = 76});

  final double size;

  static const _idleGlowAlpha = 0.18;
  static const _activeGlowAlpha = 0.5;
  static const _idleBlur = 10.0;
  static const _activeBlur = 22.0;
  static const _idleSpread = 0.0;
  static const _activeSpread = 5.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(pttActiveProvider);
    final color = active ? AppColors.danger : AppColors.orange;
    return Listener(
      onPointerDown: (_) =>
          ref.read(pttStateProvider.notifier).startTransmitting(),
      onPointerUp: (_) =>
          ref.read(pttStateProvider.notifier).stopTransmitting(),
      onPointerCancel: (_) =>
          ref.read(pttStateProvider.notifier).stopTransmitting(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Color.lerp(color, Colors.black, 0.25)!],
            radius: 0.95,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(
                alpha: active ? _activeGlowAlpha : _idleGlowAlpha,
              ),
              blurRadius: active ? _activeBlur : _idleBlur,
              spreadRadius: active ? _activeSpread : _idleSpread,
            ),
          ],
        ),
        child: Icon(
          active ? Icons.mic_rounded : Icons.mic_none_rounded,
          color: Colors.white,
          size: size * 0.42,
        ),
      ),
    );
  }
}
