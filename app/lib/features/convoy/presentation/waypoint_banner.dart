import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/check_in_providers.dart';
import '../application/convoy_providers.dart';
import '../application/waypoint_providers.dart';
import 'route_sheet.dart';

/// Banner oberhalb des Radars: zeigt aktuellen Waypoint mit Distanz +
/// Kompassrichtung. Renders nichts wenn kein Waypoint gesetzt.
class WaypointBanner extends ConsumerWidget {
  const WaypointBanner({super.key});

  static const _compassDirs = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tour = ref.watch(tourProvider);
    final wp = tour.current;
    if (wp == null) return const SizedBox.shrink();
    final distance = ref.watch(waypointDistanceMetersProvider);
    final bearing = ref.watch(waypointBearingDegreesProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const RouteSheet(),
          ),
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Container(
            key: const ValueKey('waypoint-banner'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              border: Border.all(color: AppColors.orange, width: 1.2),
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.flag_rounded,
                    color: AppColors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'STOPP 1',
                            style: AppTextStyles.sectionLabel.copyWith(
                              fontSize: 10,
                            ),
                          ),
                          if (tour.length > 1) ...[
                            const SizedBox(width: 4),
                            Text(
                              '/ ${tour.length}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                                letterSpacing: 1.6,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        wp.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusLine(distance, bearing),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _CheckInBadge(),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _statusLine(double? distance, double? bearing) {
    if (distance == null) return 'GPS wartet …';
    return '${_formatDistance(distance)} · ${_compass(bearing)}';
  }

  static String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(meters >= 10000 ? 0 : 1)} km';
    }
    return '${meters.round()} m';
  }

  static String _compass(double? bearing) {
    if (bearing == null) return '—';
    final n = bearing % 360;
    final idx = (((n + 22.5) / 45).floor()) % 8;
    return _compassDirs[idx];
  }
}

/// Kleine Pille im WaypointBanner mit Live-Counter "X/Y" angekommen.
/// Grün wenn alle da, sonst orange. Versteckt sich wenn kein Konvoi.
class _CheckInBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convoy = ref.watch(currentConvoyProvider);
    if (convoy == null) return const SizedBox.shrink();
    final arrived = ref.watch(currentStopCheckInsProvider).length;
    final total = convoy.members.length;
    final allHere = arrived == total && total > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (allHere ? AppColors.success : AppColors.orange)
            .withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: allHere ? AppColors.success : AppColors.orange,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allHere ? Icons.check_rounded : Icons.location_on_rounded,
            color: allHere ? AppColors.success : AppColors.orange,
            size: 12,
          ),
          const SizedBox(width: 3),
          Text(
            '$arrived/$total',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: allHere ? AppColors.success : AppColors.orange,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
