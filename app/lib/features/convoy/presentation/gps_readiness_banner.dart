import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Shown in the convoy view while the local device has no GPS fix. Tapping
/// "Aktivieren" drives [LocationPermissionService.ensureReady] (turn the device
/// location service on + grant the permission) so the user — and the rest of
/// the convoy — can see them on the map.
class GpsReadinessBanner extends StatelessWidget {
  const GpsReadinessBanner({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Container(
        key: const ValueKey('gps-readiness-banner'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.orange),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_off_rounded,
                color: AppColors.orange, size: 20),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(
              child: Text(
                'Kein GPS-Signal — Standort & Ortung aktivieren, damit dich '
                'der Konvoi sieht.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              key: const ValueKey('gps-activate-button'),
              onPressed: onActivate,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
              child: const Text('Aktivieren'),
            ),
          ],
        ),
      ),
    );
  }
}
