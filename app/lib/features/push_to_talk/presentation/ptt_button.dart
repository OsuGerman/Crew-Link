import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/ptt_providers.dart';

/// Hold-down Push-to-Talk-Button — Theme-konform mit Orange-Akzent.
///
/// Pointer-Events statt GestureDetector damit Recording mit dem allerersten
/// Frame des Kontakts startet (kein Tap-Delay, keine Gesture-Arena).
/// Tiefe über Helligkeit statt Glow: idle ein dezenter Haarlinien-Ring, beim
/// Senden ein SCHARFER 2px-Ring in der Senden-Farbe mit etwas Luft (Gap) zum
/// Button + ein leichter Scale-Puls. Kein weicher boxShadow-Blob mehr — der
/// zentrale Button bleibt das einzige Orange-Verlaufselement.
class PttButton extends ConsumerWidget {
  const PttButton({super.key, this.size = 76});

  final double size;

  /// Abstand des Aktiv-Rings zum Button (Luft, damit der Ring als Rahmen liest,
  /// nicht als Border am Kreis klebt).
  static const _ringGap = 5.0;
  static const _idleRingWidth = AppBorders.hairline;
  static const _activeRingWidth = 2.0;
  static const _idleRingAlpha = 0.35;
  static const _activeScale = 1.04;

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
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: active ? _activeScale : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: size + _ringGap * 2,
          height: size + _ringGap * 2,
          padding: const EdgeInsets.all(_ringGap),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? color
                  : color.withValues(alpha: _idleRingAlpha),
              width: active ? _activeRingWidth : _idleRingWidth,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, Color.lerp(color, Colors.black, 0.25)!],
                radius: 0.95,
              ),
            ),
            child: Center(
              child: Icon(
                active ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: Colors.white,
                size: size * 0.42,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
