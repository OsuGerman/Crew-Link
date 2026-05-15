import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/connection_status.dart';
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, bg, fg) = switch (status) {
      ConnectionStatus.connecting => (
          'Verbinde …',
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
      ConnectionStatus.connected => (
          '',
          Icons.check,
          scheme.surface,
          scheme.onSurface,
        ),
    };

    return Container(
      key: const ValueKey('map-status-banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: bg,
      child: Row(
        children: [
          Icon(icon, color: fg, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: fg, fontSize: 13)),
        ],
      ),
    );
  }
}
