import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';
import '../application/lost_connection_watcher.dart';

/// Persistent banner listing every convoy member currently beyond the
/// proximity threshold. Unlike the event-driven ProximityWarning banner,
/// this derives state from the live position snapshot and remains visible
/// as long as a member stays out of range.
///
/// Farbsystem: AppColors.danger/dangerSurface statt scheme.errorContainer —
/// die M3-Container-Töne wirken in der dunklen App fremd.
class LostConnectionBanner extends ConsumerWidget {
  const LostConnectionBanner({super.key});

  static const double _iconSize = 18;
  static const double _fontSize = 13;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convoy = ref.watch(currentConvoyProvider);
    final lostIds = ref.watch(lostMembersProvider);
    if (convoy == null || lostIds.isEmpty) return const SizedBox.shrink();

    final names = lostIds.map((id) {
      return convoy.members
              .where((m) => m.id == id)
              .firstOrNull
              ?.displayName ??
          id;
    }).join(', ');
    final threshold = convoy.proximityWarningMeters.toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        key: const ValueKey('lost-connection-banner'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.dangerSurface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: AppColors.danger,
            width: AppBorders.hairline,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.link_off,
              color: AppColors.danger,
              size: _iconSize,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$names: mehr als $threshold m entfernt',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: _fontSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
