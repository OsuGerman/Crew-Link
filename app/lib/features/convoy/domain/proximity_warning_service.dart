import 'dart:async';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/gps_update.dart';
import 'proximity_warning.dart';

/// Watches incoming GPS updates and emits a [ProximityWarning] when any
/// other convoy member crosses the configured threshold relative to the
/// local member.
///
/// Hysteresis: once a warning fires for a member, no further warning is
/// emitted until that member moves further than `thresholdMeters * 1.2`
/// (release band) — prevents flicker at the boundary.
///
/// Stale-position filter: a warning is suppressed if *either* the local
/// or the peer position has not been refreshed within [maxPositionAge].
/// Without this, a peer that went offline (tunnel, dead battery) would
/// keep firing warnings against their last known location.
class ProximityWarningService {
  ProximityWarningService({
    required this.selfMemberId,
    required this.thresholdMeters,
    this.maxPositionAge = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String selfMemberId;
  final double thresholdMeters;
  final Duration maxPositionAge;
  final DateTime Function() _clock;

  final Map<String, GpsUpdate> _latestByMember = <String, GpsUpdate>{};
  final Set<String> _warned = <String>{};

  final StreamController<ProximityWarning> _warnings =
      StreamController<ProximityWarning>.broadcast();

  Stream<ProximityWarning> get warnings => _warnings.stream;

  double get _releaseDistance => thresholdMeters * 1.2;

  /// Feed a GPS update from any member (including self). Triggers a
  /// warning evaluation against the most recent self position.
  void ingest(GpsUpdate update) {
    _latestByMember[update.memberId] = update;
    final selfPos = _latestByMember[selfMemberId];
    if (selfPos == null) {
      return;
    }
    if (update.memberId == selfMemberId) {
      _evaluateAllAgainstSelf(selfPos);
      return;
    }
    _evaluateAgainstSelf(selfPos, update);
  }

  void _evaluateAllAgainstSelf(GpsUpdate selfPos) {
    for (final entry in _latestByMember.entries) {
      if (entry.key == selfMemberId) {
        continue;
      }
      _evaluateAgainstSelf(selfPos, entry.value);
    }
  }

  void _evaluateAgainstSelf(GpsUpdate selfPos, GpsUpdate other) {
    if (_isStale(selfPos) || _isStale(other)) {
      return;
    }

    final distance = haversineMeters(
      lat1: selfPos.latitude,
      lon1: selfPos.longitude,
      lat2: other.latitude,
      lon2: other.longitude,
    );

    final wasWarned = _warned.contains(other.memberId);
    if (!wasWarned && distance <= thresholdMeters) {
      _warned.add(other.memberId);
      _warnings.add(ProximityWarning(
        otherMemberId: other.memberId,
        distanceMeters: distance,
        thresholdMeters: thresholdMeters,
        triggeredAt: _clock(),
      ));
    } else if (wasWarned && distance > _releaseDistance) {
      _warned.remove(other.memberId);
    }
  }

  bool _isStale(GpsUpdate update) =>
      _clock().difference(update.timestamp) > maxPositionAge;

  Future<void> dispose() async {
    await _warnings.close();
    _latestByMember.clear();
    _warned.clear();
  }
}
