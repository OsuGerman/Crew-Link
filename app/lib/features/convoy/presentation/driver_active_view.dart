import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/convoy.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/theme/app_theme.dart';
import '../../push_to_talk/presentation/ptt_button.dart';
import '../application/convoy_providers.dart';
import '../domain/proximity_warning.dart';
import 'connection_status_banner.dart';
import 'convoy_radar_view.dart';
import 'waypoint_banner.dart';

/// Driver-Mode (Design.pdf Frame 8 "Glance-only Layout").
/// Reduzierte Cognitive Load am Steuer: großer Radar, prominenter
/// Abstands-Card, Tabular-Ziffern, große Touch-Ziele.
class DriverModeActiveView extends ConsumerWidget {
  const DriverModeActiveView({
    super.key,
    required this.convoy,
    required this.onLeave,
  });

  final Convoy convoy;
  final VoidCallback onLeave;

  static const double _leaveButtonHeight = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionsAsync = ref.watch(livePositionsProvider);
    final warning = ref.watch(proximityWarningsProvider).valueOrNull;
    final positions =
        positionsAsync.valueOrNull ?? const <String, GpsUpdate>{};
    final selfMemberId = ref.watch(selfMemberIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConnectionStatusBanner(),
        if (warning != null) _DriverProximityCard(warning: warning),
        if (warning != null) const SizedBox(height: AppSpacing.md),
        const WaypointBanner(),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ConvoyRadarView(
            selfMemberId: selfMemberId,
            positions: positions,
            thresholdMeters: convoy.proximityWarningMeters,
            maxHeight: double.infinity,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _DriverMembersSummary(
          convoy: convoy,
          positions: positions,
          selfMemberId: selfMemberId,
        ),
        const SizedBox(height: AppSpacing.md),
        // PTT in der Mitte — größer als im Standard-Mode für Daumen-am-Lenkrad
        const Center(child: PttButton(size: 96)),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: _leaveButtonHeight,
          child: OutlinedButton.icon(
            key: const ValueKey('driver-leave-button'),
            onPressed: onLeave,
            icon: const Icon(Icons.logout_rounded, size: 26),
            label: const Text(
              'Konvoi verlassen',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger, width: 1.4),
              minimumSize: const Size.fromHeight(_leaveButtonHeight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.button),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// Großer Abstands-Card im Driver-Mode. ABSTAND-Caps + Distanz 32 px für
/// Glance-Lesbarkeit am Steuer.
class _DriverProximityCard extends StatelessWidget {
  const _DriverProximityCard({required this.warning});

  final ProximityWarning warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('driver-proximity-card'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.danger, width: 1.6),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: 28,
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
                    fontSize: 11,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${warning.distanceMeters.toStringAsFixed(0)} m zu '
                  '${warning.otherMemberId}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompakte Member-Pillen (max 4 sichtbar, danach "+N") mit Farb-Dot und
/// Distanz zu Self. Ersetzt im Driver-Mode die volle Liste.
class _DriverMembersSummary extends StatelessWidget {
  const _DriverMembersSummary({
    required this.convoy,
    required this.positions,
    required this.selfMemberId,
  });

  final Convoy convoy;
  final Map<String, GpsUpdate> positions;
  final String selfMemberId;

  static const _maxVisible = 4;
  static const _palette = <Color>[
    Color(0xFF4F8DFD),
    Color(0xFF22C55E),
    Color(0xFFE94560),
    Color(0xFFA855F7),
    Color(0xFFFFC53D),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
  ];

  Color _colorFor(String memberId) {
    final hash = memberId.codeUnits.fold<int>(0, (a, c) => a + c);
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final selfPos = positions[selfMemberId];
    final peers = positions.entries
        .where((e) => e.key != selfMemberId)
        .map((e) {
      final d = selfPos == null
          ? null
          : haversineMeters(
              lat1: selfPos.latitude,
              lon1: selfPos.longitude,
              lat2: e.value.latitude,
              lon2: e.value.longitude,
            );
      final member = convoy.members
          .where((m) => m.id == e.key)
          .firstOrNull;
      return (
        id: e.key,
        name: member?.displayName ?? e.key,
        distance: d,
      );
    }).toList()
      ..sort((a, b) =>
          (a.distance ?? double.infinity).compareTo(b.distance ?? double.infinity));

    final visible = peers.take(_maxVisible).toList();
    final overflow = peers.length - visible.length;

    return Container(
      key: const ValueKey('driver-members-summary'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.surfaceOutline, width: 0.6),
      ),
      child: Row(
        children: [
          const Icon(Icons.group_rounded,
              color: AppColors.orange, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${convoy.members.length}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final peer in visible)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: _MemberPill(
                        color: _colorFor(peer.id),
                        name: peer.name,
                        distance: peer.distance,
                      ),
                    ),
                  if (overflow > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: Container(
                        height: 30,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          '+$overflow',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberPill extends StatelessWidget {
  const _MemberPill({
    required this.color,
    required this.name,
    required this.distance,
  });

  final Color color;
  final String name;
  final double? distance;

  String _distLabel() {
    final d = distance;
    if (d == null) return '–';
    if (d < 1000) return '${d.toStringAsFixed(0)} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '${name.length > 6 ? '${name.substring(0, 6)}…' : name} '
            '${_distLabel()}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
