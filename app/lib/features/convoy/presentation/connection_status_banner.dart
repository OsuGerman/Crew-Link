import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/connection_status.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';
import 'accent_banner.dart';

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
    // Streifenfarbe = Statussignal; Icon/Text in der Statusfarbe (fg).
    // connecting = neutral, reconnecting = warning, offline = danger.
    final (label, icon, stripe, fg) = switch (status) {
      ConnectionStatus.connecting => (
          'Verbinde mit Konvoi …',
          Icons.sync,
          AppColors.surfaceOutline,
          AppColors.textSecondary,
        ),
      ConnectionStatus.reconnecting => (
          'Verbindung verloren · versuche erneut …',
          Icons.cloud_off,
          AppColors.warning,
          AppColors.warning,
        ),
      ConnectionStatus.offline => (
          'Offline',
          Icons.signal_wifi_off,
          AppColors.danger,
          AppColors.danger,
        ),
      ConnectionStatus.connected => (
          '',
          Icons.check,
          AppColors.surfaceOutline,
          AppColors.textPrimary,
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AccentBanner(
        bannerKey: const ValueKey('connection-status-banner'),
        stripeColor: stripe,
        padding: const EdgeInsets.all(AppSpacing.md),
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
