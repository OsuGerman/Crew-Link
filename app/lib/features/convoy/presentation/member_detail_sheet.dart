import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/convoy_member.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/models/vehicle_mod.dart';
import '../../../core/models/vehicle_profile.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';

/// Modaler Bottom-Sheet mit Detail-Infos zu einem Mitglied.
/// Zeigt: Avatar + Name + Badges, Fahrzeug-Hero-Card mit Specs, Mod-Chips,
/// Live-Stats (Distanz, Speed, Bearing, last-seen).
///
/// Aufgerufen aus `ConvoyMemberList` per Tap auf eine Row.
class MemberDetailSheet extends ConsumerWidget {
  const MemberDetailSheet({
    super.key,
    required this.member,
    required this.memberColor,
  });

  final ConvoyMember member;
  final Color memberColor;

  static const _compassDirs = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];

  static const _categoryColors = <String, Color>{
    'engine': Color(0xFFE94560),
    'wheels': Color(0xFF4F8DFD),
    'exterior': Color(0xFFFF6B2C),
    'interior': Color(0xFFA855F7),
    'audio': Color(0xFF06B6D4),
    'electronics': Color(0xFF22C55E),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfId = ref.watch(selfMemberIdProvider);
    final positions = ref.watch(livePositionsProvider).valueOrNull;
    final memberPos = positions?[member.id];
    final selfPos = positions?[selfId];
    final isSelf = member.id == selfId;

    final distance = (memberPos == null || selfPos == null || isSelf)
        ? null
        : haversineMeters(
            lat1: selfPos.latitude,
            lon1: selfPos.longitude,
            lat2: memberPos.latitude,
            lon2: memberPos.longitude,
          );
    final bearing = (memberPos == null || selfPos == null || isSelf)
        ? null
        : bearingDegrees(
            lat1: selfPos.latitude,
            lon1: selfPos.longitude,
            lat2: memberPos.latitude,
            lon2: memberPos.longitude,
          );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl,
        ),
        child: SingleChildScrollView(
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
              _MemberHero(
                member: member,
                color: memberColor,
                isSelf: isSelf,
              ),
              if (member.vehicle != null) ...[
                const SizedBox(height: AppSpacing.xl),
                _VehicleCard(vehicle: member.vehicle!),
                if (member.vehicle!.mods.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SectionLabel(label: 'MODS · ${member.vehicle!.mods.length}'),
                  const SizedBox(height: AppSpacing.sm),
                  _ModChipsWrap(
                    mods: member.vehicle!.mods,
                    colorFor: (cat) =>
                        _categoryColors[cat] ?? AppColors.textSecondary,
                  ),
                ],
              ] else if (!isSelf) ...[
                const SizedBox(height: AppSpacing.xl),
                _NoVehicleHint(displayName: member.displayName),
              ],
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel(label: 'LIVE'),
              const SizedBox(height: AppSpacing.sm),
              _LiveStatsGrid(
                update: memberPos,
                distance: distance,
                bearing: bearing,
                isSelf: isSelf,
              ),
              const SizedBox(height: AppSpacing.lg),
              _MemberIdRow(memberId: member.id),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) =>
      Text(label, style: AppTextStyles.sectionLabel);
}

class _MemberHero extends StatelessWidget {
  const _MemberHero({
    required this.member,
    required this.color,
    required this.isSelf,
  });

  final ConvoyMember member;
  final Color color;
  final bool isSelf;

  String _initials() {
    final src = member.displayName.trim();
    if (src.isEmpty) return '?';
    final parts = src.split(RegExp(r'\s+'));
    final first = parts.first.characters.first.toUpperCase();
    if (parts.length == 1) return first;
    return first + parts[1].characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.28),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            _initials(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
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
                'MITGLIED',
                style: AppTextStyles.sectionLabel.copyWith(fontSize: 10),
              ),
              const SizedBox(height: 2),
              Text(
                member.displayName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                children: [
                  if (isSelf)
                    const _BadgeChip(label: 'Du', color: AppColors.success),
                  if (member.isLeader)
                    const _BadgeChip(
                        label: 'Leader', color: AppColors.orange),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});
  final VehicleProfile vehicle;

  int? _powerPs() {
    final kw = vehicle.powerKw;
    if (kw == null) return null;
    return (kw * 1.35962).round();
  }

  String _drivetrainLabel() {
    switch (vehicle.drivetrain) {
      case 'FWD':
        return 'Vorderrad';
      case 'RWD':
        return 'Hinterrad';
      case 'AWD':
        return 'Allrad';
      case '4WD':
        return 'Allrad gesperrt';
      default:
        return '–';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = _powerPs();
    final subtitleParts = [
      if (vehicle.year != null) '${vehicle.year}',
      if (ps != null) '$ps PS',
      if (vehicle.color != null && vehicle.color!.isNotEmpty) vehicle.color!,
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.orange.withValues(alpha: 0.14),
            AppColors.surfaceHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
            color: AppColors.orange.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.surfaceOutline, width: 0.6),
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  color: AppColors.orange,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'FAHRZEUG',
                      style: AppTextStyles.sectionLabel.copyWith(fontSize: 10),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${vehicle.make} ${vehicle.model}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitleParts.join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (vehicle.drivetrain != null ||
              vehicle.displacement != null ||
              vehicle.transmissionType != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(color: AppColors.surfaceOutline, height: 0.6),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (vehicle.drivetrain != null)
                  Expanded(
                    child: _StatTile(
                      label: 'ANTRIEB',
                      value: _drivetrainLabel(),
                    ),
                  ),
                if (vehicle.displacement != null)
                  Expanded(
                    child: _StatTile(
                      label: 'HUBRAUM',
                      value: '${vehicle.displacement} ccm',
                    ),
                  ),
                if (vehicle.transmissionType != null)
                  Expanded(
                    child: _StatTile(
                      label: 'GETRIEBE',
                      value: _transmissionLabel(vehicle.transmissionType!),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _transmissionLabel(String t) {
    switch (t) {
      case 'manual':
        return 'Manuell';
      case 'automatic':
        return 'Automatik';
      case 'dct':
        return 'DCT';
      case 'cvt':
        return 'CVT';
      case 'electric':
        return 'Elektrisch';
      default:
        return t;
    }
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _NoVehicleHint extends StatelessWidget {
  const _NoVehicleHint({required this.displayName});
  final String displayName;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.surfaceOutline, width: 0.6),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_outlined,
              color: AppColors.textMuted, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '$displayName hat noch kein Fahrzeug hinterlegt.',
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

class _ModChipsWrap extends StatelessWidget {
  const _ModChipsWrap({required this.mods, required this.colorFor});
  final List<VehicleMod> mods;
  final Color Function(String? category) colorFor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final mod in mods)
          _ModReadOnlyChip(mod: mod, color: colorFor(mod.category)),
      ],
    );
  }
}

class _ModReadOnlyChip extends StatelessWidget {
  const _ModReadOnlyChip({required this.mod, required this.color});
  final VehicleMod mod;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            mod.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveStatsGrid extends StatelessWidget {
  const _LiveStatsGrid({
    required this.update,
    required this.distance,
    required this.bearing,
    required this.isSelf,
  });

  final GpsUpdate? update;
  final double? distance;
  final double? bearing;
  final bool isSelf;

  static const _compassDirs = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];

  String _compass(double? b) {
    if (b == null) return '—';
    final n = b % 360;
    return _compassDirs[(((n + 22.5) / 45).floor()) % 8];
  }

  String _distLabel() {
    if (isSelf) return 'Du';
    final d = distance;
    if (d == null) return '—';
    if (d < 1000) return '${d.toStringAsFixed(0)} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  String _speedLabel() {
    final u = update;
    if (u == null) return '—';
    return '${(u.speedMps * 3.6).toStringAsFixed(0)} km/h';
  }

  String _lastSeenLabel() {
    final u = update;
    if (u == null) return '—';
    final t = u.timestamp.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
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
          Row(
            children: [
              Expanded(child: _LiveStat(label: 'DISTANZ', value: _distLabel())),
              const _DividerVert(),
              Expanded(child: _LiveStat(label: 'TEMPO', value: _speedLabel())),
            ],
          ),
          const Divider(color: AppColors.surfaceOutline, height: 0.6),
          Row(
            children: [
              Expanded(
                child: _LiveStat(label: 'RICHTUNG', value: _compass(bearing)),
              ),
              const _DividerVert(),
              Expanded(
                child: _LiveStat(label: 'LETZTE', value: _lastSeenLabel()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveStat extends StatelessWidget {
  const _LiveStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
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

class _DividerVert extends StatelessWidget {
  const _DividerVert();
  @override
  Widget build(BuildContext context) => Container(
        width: 0.6,
        height: 56,
        color: AppColors.surfaceOutline,
      );
}

class _MemberIdRow extends StatelessWidget {
  const _MemberIdRow({required this.memberId});
  final String memberId;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.fingerprint_rounded,
            color: AppColors.textMuted, size: 14),
        const SizedBox(width: 4),
        Text(
          memberId,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
