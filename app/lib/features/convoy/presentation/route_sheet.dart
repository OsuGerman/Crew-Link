import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/convoy_member.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/theme/app_theme.dart';
import '../application/check_in_providers.dart';
import '../application/convoy_providers.dart';
import '../application/waypoint_providers.dart';
import '../domain/waypoint.dart';
import '../domain/waypoint_check_in.dart';
import '../domain/waypoint_tour.dart';

/// Bottom-Sheet zum Verwalten der Routenplanung (Tour).
///
/// Read-only für Member; Leader kann:
///   • Stopps hinzufügen (aktuelle GPS-Position + Label)
///   • Einzelne Stopps entfernen
///   • Tour vorrücken („Stopp erreicht")
///   • Komplette Tour löschen
class RouteSheet extends ConsumerStatefulWidget {
  const RouteSheet({super.key});

  @override
  ConsumerState<RouteSheet> createState() => _RouteSheetState();
}

class _RouteSheetState extends ConsumerState<RouteSheet> {
  final _labelCtrl = TextEditingController();
  bool _addingMode = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  void _appendStop(GpsUpdate selfPos, String selfId) {
    final label = _labelCtrl.text.trim();
    ref.read(tourProvider.notifier).addStop(
          Waypoint(
            latitude: selfPos.latitude,
            longitude: selfPos.longitude,
            label: label.isEmpty
                ? 'Stopp ${ref.read(tourProvider).length + 1}'
                : label,
            setBy: selfId,
            setAt: DateTime.now().toUtc(),
          ),
        );
    _labelCtrl.clear();
    setState(() => _addingMode = false);
  }

  @override
  Widget build(BuildContext context) {
    final tour = ref.watch(tourProvider);
    final isLeader = ref.watch(selfIsLeaderProvider);
    final selfId = ref.watch(selfMemberIdProvider);
    final positions = ref.watch(livePositionsProvider).valueOrNull;
    final selfPos = positions?[selfId];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.md, AppSpacing.xl,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pull-Handle
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
            Text(
              'ROUTE',
              style: AppTextStyles.sectionLabel,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              tour.isEmpty
                  ? 'Kein Plan'
                  : '${tour.length} Stopp${tour.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isLeader
                  ? 'Leader · setze Stopps in Reihenfolge.\n'
                      'Sichtbar für alle Mitglieder.'
                  : 'Stopps werden vom Leader gesetzt.\n'
                      'Aktueller Ziel-Stopp leuchtet orange.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (tour.isEmpty)
              _EmptyState(isLeader: isLeader)
            else ...[
              _StopList(
                tour: tour,
                isLeader: isLeader,
                selfPos: selfPos,
                onRemove: (i) =>
                    ref.read(tourProvider.notifier).removeAt(i),
              ),
              const SizedBox(height: AppSpacing.md),
              _CheckInRow(selfId: selfId),
            ],
            if (isLeader) ...[
              const SizedBox(height: AppSpacing.lg),
              if (_addingMode)
                _AddStopInline(
                  controller: _labelCtrl,
                  selfPos: selfPos,
                  onSubmit: selfPos == null
                      ? null
                      : () => _appendStop(selfPos, selfId),
                  onCancel: () {
                    _labelCtrl.clear();
                    setState(() => _addingMode = false);
                  },
                )
              else
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        key: const ValueKey('route-add-stop'),
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: const Text('Stopp hinzufügen'),
                        onPressed: () =>
                            setState(() => _addingMode = true),
                      ),
                    ),
                    if (tour.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('route-advance'),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Erreicht'),
                          onPressed: () =>
                              ref.read(tourProvider.notifier).advance(),
                        ),
                      ),
                    ],
                  ],
                ),
              if (tour.isNotEmpty && !_addingMode) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.danger),
                  label: const Text(
                    'Tour löschen',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  onPressed: () =>
                      ref.read(tourProvider.notifier).clear(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isLeader});
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.surfaceOutline, width: 0.6),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_outlined,
              color: AppColors.textMuted, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              isLeader
                  ? 'Noch keine Stopps. Tippe „Stopp hinzufügen" um '
                      'den ersten Halt zu setzen.'
                  : 'Der Leader hat noch keinen Routenplan erstellt.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopList extends StatelessWidget {
  const _StopList({
    required this.tour,
    required this.isLeader,
    required this.selfPos,
    required this.onRemove,
  });

  final WaypointTour tour;
  final bool isLeader;
  final GpsUpdate? selfPos;
  final void Function(int index) onRemove;

  String _distLabel(Waypoint wp) {
    final p = selfPos;
    if (p == null) return '—';
    final d = haversineMeters(
      lat1: p.latitude,
      lon1: p.longitude,
      lat2: wp.latitude,
      lon2: wp.longitude,
    );
    if (d < 1000) return '${d.toStringAsFixed(0)} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.surfaceOutline, width: 0.6),
      ),
      child: Column(
        children: [
          for (var i = 0; i < tour.stops.length; i++)
            _StopRow(
              index: i,
              stop: tour.stops[i],
              isCurrent: i == 0,
              isLast: i == tour.stops.length - 1,
              distanceLabel: i == 0 ? _distLabel(tour.stops[i]) : null,
              onRemove: isLeader ? () => onRemove(i) : null,
            ),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.index,
    required this.stop,
    required this.isCurrent,
    required this.isLast,
    required this.distanceLabel,
    required this.onRemove,
  });

  final int index;
  final Waypoint stop;
  final bool isCurrent;
  final bool isLast;
  final String? distanceLabel;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final accentColor =
        isCurrent ? AppColors.orange : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(
                  color: AppColors.surfaceOutline,
                  width: 0.4,
                ),
              ),
      ),
      child: Row(
        children: [
          // Numbered circle
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppColors.orange
                  : AppColors.surfaceHigh,
              shape: BoxShape.circle,
              border: Border.all(
                color: accentColor,
                width: 1.2,
              ),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isCurrent ? Colors.white : AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stop.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isCurrent
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (distanceLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Aktuell · $distanceLabel',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.orange,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(
                minWidth: 32, minHeight: 32,
              ),
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const Icon(Icons.close_rounded,
                  color: AppColors.textMuted),
              tooltip: 'Stopp entfernen',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

/// "Bin da"-Row direkt unter der Stop-Liste. Zeigt links den Check-In-
/// Counter, rechts den Action-Button. Member sieht "Eingecheckt" wenn er
/// schon bestätigt hat.
class _CheckInRow extends ConsumerWidget {
  const _CheckInRow({required this.selfId});
  final String selfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convoy = ref.watch(currentConvoyProvider);
    if (convoy == null) return const SizedBox.shrink();
    final checkIns = ref.watch(currentStopCheckInsProvider);
    final hasCheckedIn = ref.watch(selfHasCheckedInProvider);
    final totalMembers = convoy.members.length;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: checkIns.length == totalMembers && totalMembers > 0
              ? AppColors.success
              : AppColors.surfaceOutline,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ANGEKOMMEN',
                  style: AppTextStyles.sectionLabel.copyWith(fontSize: 10),
                ),
                const SizedBox(height: 2),
                Text(
                  '${checkIns.length} / $totalMembers Mitglieder',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (checkIns.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _arrivedNames(checkIns.toList(), convoy.members),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (hasCheckedIn)
            const _BadgePill(
              label: 'Eingecheckt',
              color: AppColors.success,
            )
          else
            FilledButton.icon(
              key: const ValueKey('route-check-in'),
              icon: const Icon(Icons.location_on_rounded, size: 18),
              label: const Text('Bin da'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () => ref
                  .read(checkInsProvider.notifier)
                  .checkInAtCurrentStop(selfId),
            ),
        ],
      ),
    );
  }

  String _arrivedNames(
    List<WaypointCheckIn> checkIns,
    List<ConvoyMember> members,
  ) {
    final names = <String>[];
    for (final ci in checkIns) {
      final m = members.where((m) => m.id == ci.memberId).firstOrNull;
      names.add(m?.displayName ?? ci.memberId);
    }
    return names.join(', ');
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _AddStopInline extends StatelessWidget {
  const _AddStopInline({
    required this.controller,
    required this.selfPos,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final GpsUpdate? selfPos;
  final VoidCallback? onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('route-add-stop-label'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Beschreibung · z. B. Tankstelle Müller',
            labelText: 'Stopp-Name',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                child: const Text('Abbrechen'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                key: const ValueKey('route-add-stop-submit'),
                icon: const Icon(Icons.my_location_rounded),
                label: Text(
                  selfPos == null
                      ? 'Warte auf GPS …'
                      : 'Hier hinzufügen',
                ),
                onPressed: onSubmit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
