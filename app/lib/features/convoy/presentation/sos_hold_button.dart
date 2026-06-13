import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/gps_update.dart';
import '../../../core/models/hazard_report.dart';
import '../../../core/realtime/connection_status.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';
import '../application/hazard_providers.dart';

/// Broadcasts an SOS — the user's current position as a `sos` hazard — to every
/// convoy member and shows a confirmation. Synchronous; safe to call before a
/// pop because the SnackBar is enqueued on the nearest messenger immediately.
///
/// Ehrliches Feedback: ohne Verbindung wird NICHT "gesendet" behauptet —
/// der SOS-Frame landet dann in der Offline-Queue des Socket-Clients und
/// geht nach dem Reconnect garantiert raus; genau das sagt die SnackBar.
void broadcastSos(
  BuildContext context,
  WidgetRef ref, {
  required String convoyId,
  required GpsUpdate selfPos,
  required String selfId,
}) {
  ref.read(hazardPingsProvider.notifier).report(
        type: HazardType.sos,
        latitude: selfPos.latitude,
        longitude: selfPos.longitude,
        reporterId: selfId,
        convoyId: convoyId,
      );
  final connected = ref.read(convoySocketProvider)?.currentStatus ==
      ConnectionStatus.connected;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppColors.danger,
      content: Row(
        children: [
          const Icon(Icons.sos_rounded, color: Colors.white),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              connected
                  ? 'SOS an alle gesendet — deine Position wurde geteilt.'
                  : 'Keine Verbindung — SOS wird gesendet, sobald online.',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Hold-to-trigger SOS button (3 s, with a progress fill that guards against
/// accidental taps). A big, single touch target meant to sit directly in the
/// convoy / driver views so it's reachable at a glance while driving.
/// [onTriggered] == null disables it (e.g. no GPS fix yet).
class SosHoldButton extends StatefulWidget {
  const SosHoldButton({super.key, required this.onTriggered, this.height = 60});

  final VoidCallback? onTriggered;
  final double height;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _fired = false;

  /// Dezente Flächentönung der Ruhefläche (klarer Container, kein Glow).
  static const _surfaceTintAlpha = 0.12;
  static const _holdSeconds = 3;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_fired) {
          _fired = true;
          widget.onTriggered?.call();
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _cancel() {
    if (!_fired) _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTriggered != null;
    final color = enabled ? AppColors.danger : AppColors.textMuted;
    return GestureDetector(
      onTapDown: enabled
          ? (_) {
              _fired = false;
              _ctrl.forward(from: 0);
            }
          : null,
      onTapUp: enabled ? (_) => _cancel() : null,
      onTapCancel: enabled ? _cancel : null,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final p = _ctrl.value;
          final secondsLeft = ((1 - p) * _holdSeconds).ceil();
          // Während des Füllens steht der Inhalt auf dem soliden danger-Balken
          // → weiß für sauberen Kontrast; in Ruhe bleibt er danger-getönt,
          // damit das Gefahrensignal erhalten bleibt.
          final foreground = p > 0 ? Colors.white : color;
          return Container(
            key: const ValueKey('sos-hold-button'),
            height: widget.height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: color.withValues(alpha: _surfaceTintAlpha),
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: color, width: AppBorders.selected),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Klarer solider danger-Balken (kein Alpha-Matsch) — der
                // Fortschritt liest sich als echtes Füllen, nicht als Schleier.
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: p,
                  child: ColoredBox(color: color),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sos_rounded, color: foreground),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      !enabled
                          ? 'SOS · warte auf GPS'
                          : p > 0 && p < 1
                              ? 'Halten … ${secondsLeft}s'
                              : 'SOS · 3 Sek. halten',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
