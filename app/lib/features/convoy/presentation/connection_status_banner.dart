import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/connection_status.dart';
import '../application/convoy_providers.dart';

/// Inline banner that reflects the live `connectionStatus` of the
/// active convoy socket. Renders nothing while connected — only
/// surfaces during connecting / reconnecting / offline transitions.
class ConnectionStatusBanner extends ConsumerWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStatus = ref.watch(convoySocketStatusProvider);
    final status = asyncStatus.valueOrNull;
    if (status == null || status == ConnectionStatus.connected) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, bg, fg) = switch (status) {
      ConnectionStatus.connecting => (
          'Verbinde mit Konvoi …',
          Icons.sync,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      ConnectionStatus.reconnecting => (
          'Verbindung verloren · versuche erneut …',
          Icons.cloud_off,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      ConnectionStatus.offline => (
          'Offline',
          Icons.signal_wifi_off,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      ConnectionStatus.connected =>
        ('', Icons.check, scheme.surface, scheme.onSurface),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const ValueKey('connection-status-banner'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: fg, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
