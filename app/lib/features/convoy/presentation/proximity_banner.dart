import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/active_proximity_warning.dart';
import '../application/convoy_providers.dart';

/// Roter Abstands-Banner (Member kam zu nah) — zeigt den Roster-Anzeigenamen
/// statt der rohen UID und blendet sich nach [kProximityWarningTtl] selbst
/// aus (Zustand kommt aus [activeProximityWarningProvider]).
class ProximityBanner extends ConsumerWidget {
  const ProximityBanner({super.key});

  static const double _iconPlateSize = 36;
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warning = ref.watch(activeProximityWarningProvider);
    if (warning == null) return const SizedBox.shrink();
    final convoy = ref.watch(currentConvoyProvider);
    final name = memberDisplayName(convoy, warning.otherMemberId);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        key: const ValueKey('proximity-banner'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.dangerSurface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.danger, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: _iconPlateSize,
              height: _iconPlateSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: _iconSize,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ABSTAND',
                    style: AppTextStyles.sectionLabel.copyWith(
                      fontSize: 10,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$name · '
                    '${warning.distanceMeters.toStringAsFixed(0)} m entfernt',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
