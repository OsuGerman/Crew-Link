import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/fuel_providers.dart';
import '../application/quick_action_providers.dart';
import '../domain/fuel_estimate.dart';
import '../domain/quick_action.dart';

/// Personal fuel tracker: a manual tank-level slider + configurable range on a
/// full tank → estimated remaining range with a green/yellow/red warning, plus
/// a one-tap "tell the convoy I need fuel" broadcast (reuses the quick-action).
class FuelSheet extends ConsumerWidget {
  const FuelSheet({super.key});

  static const _rangeStep = 50;
  static const _rangeMin = 100;
  static const _rangeMax = 1500;

  static Color _tierColor(FuelTier tier) => switch (tier) {
        FuelTier.ok => AppColors.success,
        FuelTier.low => const Color(0xFFFFC53D),
        FuelTier.critical => AppColors.danger,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(fuelLevelProvider);
    final rangeKm = ref.watch(fuelRangeKmProvider);
    final estimate = ref.watch(fuelEstimateProvider);
    final color = _tierColor(estimate.tier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceOutline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'TANKSTAND',
              style: AppTextStyles.sectionLabel,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '≈ ${estimate.remainingKm} km',
              key: const ValueKey('fuel-remaining'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Text(
              'verbleibende Reichweite',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.md),
            if (estimate.shouldWarn) _Warning(tier: estimate.tier, color: color),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Icon(Icons.local_gas_station_rounded, color: color, size: 20),
                const SizedBox(width: AppSpacing.sm),
                const Text(
                  'Tankfüllung',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(level * 100).round()} %',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Slider(
              key: const ValueKey('fuel-level-slider'),
              value: level,
              activeColor: color,
              onChanged: (v) =>
                  ref.read(fuelLevelProvider.notifier).state = v,
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Reichweite bei vollem Tank',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('fuel-range-minus'),
                  onPressed: rangeKm > _rangeMin
                      ? () => ref.read(fuelRangeKmProvider.notifier).state =
                          rangeKm - _rangeStep
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Text(
                  '$rangeKm km',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  key: const ValueKey('fuel-range-plus'),
                  onPressed: rangeKm < _rangeMax
                      ? () => ref.read(fuelRangeKmProvider.notifier).state =
                          rangeKm + _rangeStep
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              key: const ValueKey('fuel-broadcast'),
              onPressed: () {
                ref
                    .read(quickActionProvider.notifier)
                    .send(QuickActionKind.fuelStop);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    duration: Duration(seconds: 2),
                    content: Text('Tankstopp an den Konvoi gemeldet'),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.local_gas_station_rounded),
              label: const Text('Tankstopp dem Konvoi melden'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.tier, required this.color});

  final FuelTier tier;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final message = tier == FuelTier.critical
        ? 'Kritisch — jetzt tanken!'
        : 'Reichweite niedrig — plane einen Tankstopp.';
    return Container(
      key: const ValueKey('fuel-warning'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
