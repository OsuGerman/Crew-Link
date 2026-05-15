import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/hazard_report.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';
import '../application/hazard_providers.dart';

/// Horizontal-Scroll-Banner mit aktiven Gefahrenmeldungen. Jeder Pin als
/// farbige Pille mit Icon + Restzeit + Distanz. Tap = wenn-Reporter:
/// Bestätigungs-Sheet zum Entfernen.
class HazardBannerStrip extends ConsumerWidget {
  const HazardBannerStrip({super.key});

  /// Wire-Type → (Icon, Color, Display-Label) Map. Hält Strip + Quick-Sheet
  /// optisch in Sync — Reporter sieht denselben Pin in beiden Views.
  static const _meta = <HazardType, (IconData, Color, String)>{
    HazardType.trafficJam:
        (Icons.traffic_rounded, Color(0xFFE94560), 'Stau'),
    HazardType.accident:
        (Icons.car_crash_rounded, Color(0xFFFF6B2C), 'Unfall'),
    HazardType.construction:
        (Icons.construction_rounded, Color(0xFFFFC53D), 'Baustelle'),
    HazardType.obstacle:
        (Icons.warning_amber_rounded, Color(0xFFFFC53D), 'Hindernis'),
    HazardType.slipperyRoad:
        (Icons.water_drop_rounded, Color(0xFF4F8DFD), 'Glätte'),
    HazardType.poorVisibility:
        (Icons.foggy, Color(0xFF6B6B73), 'Sicht'),
    HazardType.brokenDownVehicle: (
      Icons.directions_car_filled_rounded,
      Color(0xFFA855F7),
      'Panne'
    ),
    HazardType.policeCheckpoint:
        (Icons.local_police_rounded, Color(0xFF06B6D4), 'Polizei'),
    HazardType.other:
        (Icons.help_outline_rounded, Color(0xFF6B6B73), 'Sonstiges'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hazards = ref.watch(hazardPingsProvider);
    if (hazards.isEmpty) return const SizedBox.shrink();
    final selfId = ref.watch(selfMemberIdProvider);
    final positions = ref.watch(livePositionsProvider).valueOrNull;
    final selfPos = positions?[selfId];

    // Sortieren: nächstgelegene zuerst, ohne GPS am Ende.
    final sorted = [...hazards]..sort((a, b) {
        final da = selfPos == null
            ? double.infinity
            : haversineMeters(
                lat1: selfPos.latitude,
                lon1: selfPos.longitude,
                lat2: a.latitude,
                lon2: a.longitude,
              );
        final db = selfPos == null
            ? double.infinity
            : haversineMeters(
                lat1: selfPos.latitude,
                lon1: selfPos.longitude,
                lat2: b.latitude,
                lon2: b.longitude,
              );
        return da.compareTo(db);
      });

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SizedBox(
        key: const ValueKey('hazard-banner-strip'),
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: sorted.length,
          separatorBuilder: (_, __) =>
              const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, i) {
            final h = sorted[i];
            final meta = _meta[h.type] ?? _meta[HazardType.other]!;
            return _HazardPill(
              hazard: h,
              icon: meta.$1,
              color: meta.$2,
              label: meta.$3,
              distance: selfPos == null
                  ? null
                  : haversineMeters(
                      lat1: selfPos.latitude,
                      lon1: selfPos.longitude,
                      lat2: h.latitude,
                      lon2: h.longitude,
                    ),
              isMine: h.reporterId == selfId,
              onRemove: h.reporterId == selfId
                  ? () => ref
                      .read(hazardPingsProvider.notifier)
                      .remove(h.id)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _HazardPill extends StatelessWidget {
  const _HazardPill({
    required this.hazard,
    required this.icon,
    required this.color,
    required this.label,
    required this.distance,
    required this.isMine,
    required this.onRemove,
  });

  final HazardReport hazard;
  final IconData icon;
  final Color color;
  final String label;
  final double? distance;
  final bool isMine;
  final VoidCallback? onRemove;

  String _distLabel() {
    final d = distance;
    if (d == null) return '–';
    if (d < 1000) return '${d.toStringAsFixed(0)} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  String _ttlLabel() {
    final expiry = hazard.expiresAt;
    if (expiry == null) return '';
    final remaining = expiry.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return 'abgelaufen';
    final minutes = remaining.inMinutes;
    if (minutes < 1) return '<1 min';
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.1,
                  ),
                ),
                Text(
                  '${_distLabel()} · ${_ttlLabel()}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontFeatures: [FontFeature.tabularFigures()],
                    height: 1.3,
                  ),
                ),
              ],
            ),
            if (isMine) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.close_rounded, color: color, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}
