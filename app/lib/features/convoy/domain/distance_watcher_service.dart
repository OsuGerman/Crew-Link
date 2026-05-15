import 'dart:async';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/gps_update.dart';
import 'proximity_warning.dart';

/// Watches GPS updates and emits a [ProximityWarning] when the distance
/// between self and any other convoy member **exceeds** [thresholdMeters]
/// (default 500 m per project spec).
///
/// Hysteresis: once a breach fires, no further warning emits for that
/// member until they return within [thresholdMeters] × [_reArmFactor]
/// (= 400 m by default) — prevents flicker when hovering at the boundary.
///
/// Stale-position filter: suppresses warnings when either position is older
/// than [maxPositionAge], avoiding false positives when a member loses GPS.
class DistanceWatcherService {
  DistanceWatcherService({
    required this.selfMemberId,
    this.thresholdMeters = 500.0,
    this.maxPositionAge = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String selfMemberId;
  final double thresholdMeters;
  final Duration maxPositionAge;
  final DateTime Function() _clock;

  // Re-arm once peer is back within 80 % of the threshold (= 400 m at 500 m).
  static const double _reArmFactor = 0.8;

  final Map<String, GpsUpdate> _latest = {};
  final Set<String> _breached = {};

  final StreamController<ProximityWarning> _ctrl =
      StreamController<ProximityWarning>.broadcast();

  Stream<ProximityWarning> get warnings => _ctrl.stream;

  double get _reArmDistance => thresholdMeters * _reArmFactor;

  /// Feed a GPS update from any member (including self). Triggers breach
  /// evaluation against the most recent self position.
  void ingest(GpsUpdate update) {
    _latest[update.memberId] = update;
    final selfPos = _latest[selfMemberId];
    if (selfPos == null) return;
    if (update.memberId == selfMemberId) {
      _evaluateAll(selfPos);
      return;
    }
    _evaluate(selfPos, update);
  }

  void _evaluateAll(GpsUpdate selfPos) {
    for (final entry in _latest.entries) {
      if (entry.key == selfMemberId) continue;
      _evaluate(selfPos, entry.value);
    }
  }

  void _evaluate(GpsUpdate selfPos, GpsUpdate peer) {
    if (_isStale(selfPos) || _isStale(peer)) return;

    final distance = haversineMeters(
      lat1: selfPos.latitude,
      lon1: selfPos.longitude,
      lat2: peer.latitude,
      lon2: peer.longitude,
    );

    final wasBreached = _breached.contains(peer.memberId);
    if (!wasBreached && distance > thresholdMeters) {
      _breached.add(peer.memberId);
      _ctrl.add(ProximityWarning(
        otherMemberId: peer.memberId,
        distanceMeters: distance,
        thresholdMeters: thresholdMeters,
        triggeredAt: _clock(),
      ));
    } else if (wasBreached && distance <= _reArmDistance) {
      _breached.remove(peer.memberId);
    }
  }

  bool _isStale(GpsUpdate u) =>
      _clock().difference(u.timestamp) > maxPositionAge;

  Future<void> dispose() async {
    await _ctrl.close();
    _latest.clear();
    _breached.clear();
  }
}
