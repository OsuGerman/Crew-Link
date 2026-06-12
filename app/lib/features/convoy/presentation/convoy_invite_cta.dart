import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Prominent call-to-action to invite others, shown while you are alone in the
/// convoy. Getting people in is the most important first action but is
/// otherwise only reachable via a small app-bar share icon — this surfaces it
/// in the same prominent style as the route CTA. (The invite code itself lives
/// in the status header, so it is deliberately not repeated here.)
class ConvoyInviteCta extends StatelessWidget {
  const ConvoyInviteCta({super.key, required this.onInvite});

  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('convoy-invite-cta'),
          onTap: onInvite,
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
                    Icons.person_add_alt_1_rounded,
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
                        'Freunde einladen',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tippen kopiert den Einladungslink zum Teilen.',
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
