import 'package:flutter/material.dart';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/convoy.dart';
import '../../../core/models/convoy_member.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/models/vehicle_profile.dart';
import '../../../core/theme/app_theme.dart';
import 'member_detail_sheet.dart';

/// Live-Mitgliederliste — dunkles Theme, kompakte Rows mit konsistentem
/// Farb-Dot pro Member-ID, Name + Vehicle/Mod-Info links, Distanz rechts.
///
/// Designvorlage: Design.pdf Frame 5 (Member-Liste unter dem Radar).
class ConvoyMemberList extends StatelessWidget {
  const ConvoyMemberList({
    super.key,
    required this.convoy,
    required this.positions,
    required this.selfMemberId,
  });

  final Convoy convoy;
  final Map<String, GpsUpdate> positions;
  final String selfMemberId;

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    return Container(
      key: const ValueKey('live-members-tile'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.surfaceOutline, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  'MITGLIEDER',
                  style: AppTextStyles.sectionLabel.copyWith(fontSize: 11),
                ),
                const Spacer(),
                Text(
                  entries.isEmpty
                      ? 'kein GPS'
                      : '${entries.length} live · ${convoy.members.length} total',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (entries.isNotEmpty)
            const Divider(
              color: AppColors.surfaceOutline,
              height: 0.6,
              thickness: 0.6,
            ),
          for (final entry in entries) _MemberRow(entry: entry),
        ],
      ),
    );
  }

  List<_Entry> _entries() {
    final selfPos = positions[selfMemberId];
    final entries = <_Entry>[];
    for (final update in positions.values) {
      final member = _lookupMember(update.memberId);
      final distance = (selfPos == null || update.memberId == selfMemberId)
          ? null
          : haversineMeters(
              lat1: selfPos.latitude,
              lon1: selfPos.longitude,
              lat2: update.latitude,
              lon2: update.longitude,
            );
      entries.add(_Entry(
        memberId: update.memberId,
        displayName: member?.displayName ?? update.memberId,
        isLeader: member?.isLeader ?? false,
        isSelf: update.memberId == selfMemberId,
        update: update,
        distanceMeters: distance,
        vehicle: member?.vehicle,
      ));
    }
    entries.sort(_compare);
    return entries;
  }

  ConvoyMember? _lookupMember(String memberId) {
    for (final m in convoy.members) {
      if (m.id == memberId) return m;
    }
    return null;
  }

  static int _compare(_Entry a, _Entry b) {
    if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
    final ad = a.distanceMeters ?? double.infinity;
    final bd = b.distanceMeters ?? double.infinity;
    final cmp = ad.compareTo(bd);
    if (cmp != 0) return cmp;
    return a.memberId.compareTo(b.memberId);
  }
}

class _Entry {
  const _Entry({
    required this.memberId,
    required this.displayName,
    required this.isLeader,
    required this.isSelf,
    required this.update,
    required this.distanceMeters,
    required this.vehicle,
  });

  final String memberId;
  final String displayName;
  final bool isLeader;
  final bool isSelf;
  final GpsUpdate update;
  final double? distanceMeters;
  final VehicleProfile? vehicle;
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.entry});

  final _Entry entry;

  /// Erweiterte Member-Farb-Palette (konsistent zur Radar-View).
  /// Hash-basierte Zuordnung — jeder Member bekommt die gleiche Farbe in
  /// Radar, Liste und Map.
  static const _palette = <Color>[
    Color(0xFFFF6B2C), // Brand orange — für self überspringen
    Color(0xFF4F8DFD), // Cyan-blue
    Color(0xFF22C55E), // Green
    Color(0xFFE94560), // Coral-red
    Color(0xFFA855F7), // Purple
    Color(0xFFFFC53D), // Amber
    Color(0xFF06B6D4), // Teal
    Color(0xFFEC4899), // Pink
  ];

  static const _msToKmhFactor = 3.6;

  Color _memberColor() {
    if (entry.isSelf) return AppColors.orange;
    final hash = entry.memberId.codeUnits.fold<int>(0, (a, c) => a + c);
    // Skip index 0 (orange) for non-self to avoid color clash with self.
    return _palette[(hash % (_palette.length - 1)) + 1];
  }

  String _initials() {
    final source = entry.displayName.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+'));
    final first = parts.first.characters.first.toUpperCase();
    if (parts.length == 1) return first;
    return first + parts[1].characters.first.toUpperCase();
  }

  String _distanceLabel() {
    if (entry.isSelf) return 'Du';
    final d = entry.distanceMeters;
    if (d == null) return '–';
    if (d < 1000) return '${d.toStringAsFixed(0)} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  String? _vehicleLabel() {
    final v = entry.vehicle;
    if (v == null) return null;
    if (v.mods.isEmpty) return v.headline;
    return '${v.headline} · ${v.mods.length} Mods';
  }

  @override
  Widget build(BuildContext context) {
    final color = _memberColor();
    final speedKmh = entry.update.speedMps * _msToKmhFactor;
    final vehicleLabel = _vehicleLabel();
    return Material(
      key: ValueKey('member-row-${entry.memberId}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => MemberDetailSheet(
            member: ConvoyMember(
              id: entry.memberId,
              displayName: entry.displayName,
              vehicle: entry.vehicle,
              isLeader: entry.isLeader,
            ),
            memberColor: color,
          ),
        ),
        child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          // Color-Dot + Initial-Avatar
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.6),
            ),
            child: Text(
              _initials(),
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Name + Vehicle/Speed
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (entry.isLeader)
                      const _Badge(label: 'Leader', color: AppColors.orange),
                    if (entry.isSelf)
                      const _Badge(label: 'Du', color: AppColors.success),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  vehicleLabel == null
                      ? '${speedKmh.toStringAsFixed(0)} km/h'
                      : '$vehicleLabel · ${speedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Distance pill
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm + 2,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              _distanceLabel(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
        ),  // Padding
      ),  // InkWell
    );  // Material
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
