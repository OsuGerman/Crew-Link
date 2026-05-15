import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/convoy_providers.dart';
import '../application/lost_connection_watcher.dart';

/// Persistent banner listing every convoy member currently beyond the
/// proximity threshold. Unlike the event-driven ProximityWarning banner,
/// this derives state from the live position snapshot and remains visible
/// as long as a member stays out of range.
class LostConnectionBanner extends ConsumerWidget {
  const LostConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convoy = ref.watch(currentConvoyProvider);
    final lostIds = ref.watch(lostMembersProvider);
    if (convoy == null || lostIds.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final names = lostIds.map((id) {
      return convoy.members
              .where((m) => m.id == id)
              .firstOrNull
              ?.displayName ??
          id;
    }).join(', ');
    final threshold = convoy.proximityWarningMeters.toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: const ValueKey('lost-connection-banner'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.link_off, color: scheme.onErrorContainer, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$names: mehr als $threshold m entfernt',
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
