import 'package:flutter/material.dart';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/convoy.dart';
import '../../../core/models/convoy_member.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/models/vehicle_profile.dart';

/// Driver-friendly live member list with avatar, distance-from-self,
/// "Du" / "Anführer" badges and last-seen timestamp. Source of truth:
/// the live position snapshot from the WebSocket session; convoy.members
/// is layered on top to provide display names and leader status.
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
    return Card(
      key: const ValueKey('live-members-tile'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text(
              '${convoy.members.length} Mitglieder im Konvoi',
            ),
            subtitle: Text(
              entries.isEmpty
                  ? 'noch keine Live-GPS-Daten'
                  : '${entries.length} live',
            ),
          ),
          if (entries.isNotEmpty) const Divider(height: 1),
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

  static const _palette = <Color>[
    Color(0xFF3949AB),
    Color(0xFF00897B),
    Color(0xFFD81B60),
    Color(0xFFFB8C00),
    Color(0xFF6D4C41),
    Color(0xFF5E35B1),
  ];
  static const double _msToKmhFactor = 3.6;

  Color _avatarColor() {
    final hash = entry.memberId.codeUnits.fold<int>(
      0,
      (acc, c) => acc + c,
    );
    return _palette[hash % _palette.length];
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
    if (entry.isSelf) return 'Du · hier';
    final d = entry.distanceMeters;
    if (d == null) return 'Distanz wird ermittelt';
    if (d < 1000) return '${d.toStringAsFixed(0)} m entfernt';
    return '${(d / 1000).toStringAsFixed(1)} km entfernt';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final speedKmh = entry.update.speedMps * _msToKmhFactor;
    final hh = entry.update.timestamp.toLocal().hour.toString().padLeft(2, '0');
    final mm = entry.update.timestamp.toLocal().minute.toString().padLeft(2, '0');
    final ss = entry.update.timestamp.toLocal().second.toString().padLeft(2, '0');

    return ListTile(
      key: ValueKey('member-row-${entry.memberId}'),
      leading: CircleAvatar(
        backgroundColor: _avatarColor(),
        foregroundColor: Colors.white,
        child: Text(
          _initials(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (entry.isSelf) _Badge(label: 'Du', color: scheme.primary),
          if (entry.isLeader)
            _Badge(label: 'Anführer', color: scheme.tertiary),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_distanceLabel()} · ${speedKmh.toStringAsFixed(0)} km/h'),
          if (entry.vehicle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                entry.vehicle!.mods.isEmpty
                    ? entry.vehicle!.headline
                    : '${entry.vehicle!.headline} · ${entry.vehicle!.mods.length} Mods',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      trailing: Text(
        '$hh:$mm:$ss',
        style: const TextStyle(
          fontFeatures: [FontFeature.tabularFigures()],
          color: Colors.black54,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
