import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/connection_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../convoy/application/convoy_providers.dart';
import '../application/maps_providers.dart';
import 'convoy_map_widget.dart';

class ConvoyMapScreen extends ConsumerWidget {
  const ConvoyMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(memberMarkersProvider).length;
    final status = ref.watch(convoySocketStatusProvider).valueOrNull;
    final offline = status != null && status != ConnectionStatus.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          count == 0
              ? 'Live-Karte'
              : 'Live-Karte · $count Mitglied${count == 1 ? '' : 'er'}',
        ),
      ),
      body: Column(
        children: [
          if (offline) _StatusBanner(status: status),
          const Expanded(child: ConvoyMapWidget()),
        ],
      ),
    );
  }
}

/// Farbsystem: AppColors statt Material-3-Scheme-Containern — die
/// Baseline-Lila-Töne (secondary/tertiaryContainer) wirken in der dunklen
/// App fremd (Stil wie ConnectionStatusBanner/ProximityBanner).
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final ConnectionStatus status;

  static const double _iconSize = 16;
  static const double _fontSize = 13;

  @override
  Widget build(BuildContext context) {
    final (label, icon, bg, fg, borderColor) = switch (status) {
      ConnectionStatus.connecting => (
          'Verbinde …',
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0,
      ),
      child: Container(
        key: const ValueKey('map-status-banner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: borderColor, width: AppBorders.hairline),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg, size: _iconSize),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: TextStyle(color: fg, fontSize: _fontSize)),
          ],
        ),
      ),
    );
  }
}
