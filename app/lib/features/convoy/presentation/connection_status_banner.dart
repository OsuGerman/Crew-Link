import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/connection_status.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';

/// Inline banner that reflects the live `connectionStatus` of the
/// active convoy socket. Renders nothing while connected — only
/// surfaces during connecting / reconnecting / offline transitions.
///
/// Farbsystem: bewusst AppColors statt Material-3-Scheme-Containern —
/// secondary/tertiaryContainer fallen auf die Baseline-Lila-Töne zurück
/// und wirken in der dunklen App fremd (Stil wie der ProximityBanner).
class ConnectionStatusBanner extends ConsumerWidget {
  const ConnectionStatusBanner({super.key});

  static const double _iconSize = 18;
  static const double _fontSize = 13;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStatus = ref.watch(convoySocketStatusProvider);
    final status = asyncStatus.valueOrNull;
    if (status == null || status == ConnectionStatus.connected) {
      return const SizedBox.shrink();
    }
    final (label, icon, bg, fg, borderColor) = switch (status) {
      ConnectionStatus.connecting => (
          'Verbinde mit Konvoi …',
          Icons.sync,
          AppColors.surfaceHigh,
          AppColors.textSecondary,
          AppColors.surfaceOutline,
        ),
      ConnectionStatus.reconnecting => (
          'Verbindung verloren · versuche erneut …',
          Icons.cloud_off,
          AppColors.surfaceHigh,
          AppColors.warning,
          AppColors.surfaceOutline,
        ),
      ConnectionStatus.offline => (
          'Offline',
          Icons.signal_wifi_off,
          AppColors.dangerSurface,
          AppColors.danger,
          AppColors.danger,
        ),
      ConnectionStatus.connected => (
          '',
          Icons.check,
          AppColors.surface,
          AppColors.textPrimary,
          AppColors.surfaceOutline,
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        key: const ValueKey('connection-status-banner'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: borderColor, width: AppBorders.hairline),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg, size: _iconSize),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: fg, fontSize: _fontSize),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
