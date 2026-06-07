import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/convoy.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';

/// Kompakte Pille über der Bottom-Action-Bar, die die volle Mitgliederliste
/// (inkl. Grün/Gelb/Rot-Abstand + Distanzen) in einem Bottom-Sheet öffnet.
///
/// Hält die Live-Karte groß und die Member-Infos trotzdem einen Tap entfernt.
/// Zeigt "Mitglieder · N live · M gesamt", wobei N = Anzahl der Member mit
/// aktuellem GPS-Fix und M = Roster-Größe (mindestens so groß wie N, falls ein
/// frisch verbundener Member noch nicht im Roster gelandet ist).
class MembersSheetPill extends ConsumerWidget {
  const MembersSheetPill({
    super.key,
    required this.convoy,
    required this.onTap,
  });

  final Convoy convoy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, GpsUpdate> positions =
        ref.watch(livePositionsProvider).valueOrNull ??
            const <String, GpsUpdate>{};
    final liveCount = positions.length;
    final totalCount =
        convoy.members.length > liveCount ? convoy.members.length : liveCount;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('open-members-sheet'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.surfaceOutline, width: 0.8),
          ),
          child: Row(
            children: [
              const Icon(Icons.people_alt_rounded,
                  color: AppColors.orange, size: 20),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'Mitglieder',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$liveCount live · $totalCount gesamt',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.expand_less_rounded,
                  color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
