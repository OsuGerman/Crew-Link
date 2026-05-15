import 'dart:async';

import '../../../core/models/gps_update.dart';
import 'proximity_warning.dart';
import 'proximity_warning_service.dart';

/// Coordinates a live convoy session: forwards incoming GPS updates from
/// a transport stream (typically the WebSocket channel) into the
/// [ProximityWarningService] and re-broadcasts both the raw GPS feed and
/// the derived proximity warnings to UI / consumers.
///
/// The transport is passed as a raw [Stream] so this class stays
/// independent of the WebSocket implementation and is straightforward to
/// fake in tests.
class ConvoySession {
  ConvoySession({
    required this.selfMemberId,
    required Stream<GpsUpdate> incoming,
    double thresholdMeters = 500,
    Duration maxPositionAge = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : _incoming = incoming,
        _proximity = ProximityWarningService(
          selfMemberId: selfMemberId,
          thresholdMeters: thresholdMeters,
          maxPositionAge: maxPositionAge,
          clock: clock,
        );

  final String selfMemberId;
  final Stream<GpsUpdate> _incoming;
  final ProximityWarningService _proximity;

  final StreamController<GpsUpdate> _gpsRelay =
      StreamController<GpsUpdate>.broadcast();
  final StreamController<Map<String, GpsUpdate>> _positionsRelay =
      StreamController<Map<String, GpsUpdate>>.broadcast();
  final Map<String, GpsUpdate> _latestPositions = <String, GpsUpdate>{};

  StreamSubscription<GpsUpdate>? _incomingSub;
  bool _started = false;

  Stream<GpsUpdate> get gpsUpdates => _gpsRelay.stream;
  Stream<ProximityWarning> get warnings => _proximity.warnings;

  /// Latest known position for every member that has emitted at least
  /// one update during this session, keyed by `memberId`. Returned as an
  /// unmodifiable snapshot so callers cannot mutate the internal cache.
  Map<String, GpsUpdate> get latestPositions =>
      Map<String, GpsUpdate>.unmodifiable(_latestPositions);

  /// Broadcast stream of the latest-positions map. Emits an unmodifiable
  /// snapshot every time any member's position changes — consumed by the
  /// live map / member-list UI without needing to re-aggregate per event.
  Stream<Map<String, GpsUpdate>> get positions => _positionsRelay.stream;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _incomingSub = _incoming.listen(
      _onUpdate,
      onError: _gpsRelay.addError,
      cancelOnError: false,
    );
  }

  void _onUpdate(GpsUpdate update) {
    _proximity.ingest(update);
    final existing = _latestPositions[update.memberId];
    if (existing == null ||
        !update.timestamp.isBefore(existing.timestamp)) {
      _latestPositions[update.memberId] = update;
      if (!_positionsRelay.isClosed) {
        _positionsRelay.add(
          Map<String, GpsUpdate>.unmodifiable(_latestPositions),
        );
      }
    }
    if (!_gpsRelay.isClosed) {
      _gpsRelay.add(update);
    }
  }

  Future<void> dispose() async {
    await _incomingSub?.cancel();
    _incomingSub = null;
    await _proximity.dispose();
    if (!_gpsRelay.isClosed) {
      await _gpsRelay.close();
    }
    if (!_positionsRelay.isClosed) {
      await _positionsRelay.close();
    }
  }
}
