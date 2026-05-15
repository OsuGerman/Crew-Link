import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/convoy.dart';
import '../../../core/models/gps_update.dart';
import '../application/convoy_providers.dart';
import '../domain/proximity_warning.dart';
import 'connection_status_banner.dart';
import 'convoy_radar_view.dart';

/// Driver-Mode active view. Optimised for at-a-glance interaction:
/// the radar fills the bulk of the screen, a single bold proximity
/// card replaces the inline banner, and the leave button is sized
/// for a thumb on the steering wheel.
class DriverModeActiveView extends ConsumerWidget {
  const DriverModeActiveView({
    super.key,
    required this.convoy,
    required this.onLeave,
  });

  final Convoy convoy;
  final VoidCallback onLeave;

  static const double _leaveButtonHeight = 64;

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
        const SizedBox(height: 12),
        Expanded(
          child: ConvoyRadarView(
            selfMemberId: selfMemberId,
            positions: positions,
            thresholdMeters: convoy.proximityWarningMeters,
            maxHeight: double.infinity,
          ),
        ),
        const SizedBox(height: 12),
        _DriverMembersSummary(
          convoy: convoy,
          positions: positions,
          selfMemberId: selfMemberId,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: _leaveButtonHeight,
          child: FilledButton.tonalIcon(
            key: const ValueKey('driver-leave-button'),
            onPressed: onLeave,
            icon: const Icon(Icons.logout, size: 28),
            label: const Text(
              'Konvoi verlassen',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _DriverProximityCard extends StatelessWidget {
  const _DriverProximityCard({required this.warning});

  final ProximityWarning warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('driver-proximity-card'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: scheme.onErrorContainer, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ABSTAND',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  '${warning.distanceMeters.toStringAsFixed(0)} m zu ${warning.otherMemberId}',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
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

class _DriverMembersSummary extends StatelessWidget {
  const _DriverMembersSummary({
    required this.convoy,
    required this.positions,
    required this.selfMemberId,
  });

  final Convoy convoy;
  final Map<String, GpsUpdate> positions;
  final String selfMemberId;

  @override
  Widget build(BuildContext context) {
    final selfPos = positions[selfMemberId];
    double? nearestSquared;
    String? nearestMember;
    for (final entry in positions.entries) {
      if (entry.key == selfMemberId || selfPos == null) continue;
      final dx = entry.value.latitude - selfPos.latitude;
      final dy = entry.value.longitude - selfPos.longitude;
      // Squared distance is enough for picking the closest peer — saves
      // a haversine call inside what may be a per-frame rebuild.
      final sq = dx * dx + dy * dy;
      if (nearestSquared == null || sq < nearestSquared) {
        nearestSquared = sq;
        nearestMember = entry.key;
      }
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('driver-members-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.group, color: scheme.onSurface, size: 28),
          const SizedBox(width: 12),
          Text(
            '${convoy.members.length}',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'im Konvoi',
            style: TextStyle(color: scheme.onSurface, fontSize: 14),
          ),
          const Spacer(),
          if (nearestMember != null)
            Text(
              'Nächster: $nearestMember',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }
}
