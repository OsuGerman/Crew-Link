import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Auffälliger, nur für den Leader sichtbarer Call-to-Action zum Setzen eines
/// Ziels / Planen der Route. Die Straßenroute (OSRM) erscheint erst, wenn der
/// Leader ein Ziel gesetzt hat — dieser Banner macht den (sonst hinter einem
/// kleinen AppBar-Icon versteckten) Einstieg sichtbar.
class LeaderRouteCta extends StatelessWidget {
  const LeaderRouteCta({super.key, required this.onPlanRoute});

  final VoidCallback onPlanRoute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('leader-route-cta'),
          onTap: onPlanRoute,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.orange, width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.flag_rounded,
                    color: AppColors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ziel setzen · Route planen',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Lege Stopps fest — alle sehen die Route auf der Karte.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.orange,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
