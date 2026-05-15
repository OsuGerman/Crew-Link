import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import '../../../core/models/gps_update.dart';
import 'adaptive_interval.dart';
import 'platform_location_adapter.dart';

/// Maps an adaptive interval duration to OS-level [LocationSettings].
/// Injectable so unit tests never touch real platform channels.
typedef LocationSettingsFactory = LocationSettings Function(Duration interval);

/// Three OS sampling buckets derived from the 1–5 s adaptive curve.
/// Restarting the geolocator stream only on bucket transitions avoids
/// thrashing while cutting GPS hardware wake-ups when stationary.
enum _Bucket {
  fast(1000, 0),   // ≥ 30 km/h → 1 s / 0 m filter
  medium(2000, 5), // 5–30 km/h → 2 s / 5 m filter
  slow(5000, 10);  // ≤ 5 km/h  → 5 s / 10 m filter

  const _Bucket(this.intervalMs, this.distanceFilter);

  final int intervalMs;
  final int distanceFilter;

  static _Bucket fromInterval(Duration d) {
    if (d.inMilliseconds <= 1200) return fast;
    if (d.inMilliseconds <= 3500) return medium;
    return slow;
  }
}

/// GPS-Producer mit adaptivem Sampling (1–5 s).
///
/// Steuert die OS-Sampling-Rate anhand der Fahrzeuggeschwindigkeit:
/// stehend → 5 s / 10 m, Stadtfahrt → 2 s / 5 m, Autobahn → 1 s / 0 m.
/// Der geolocator-Stream wird nur bei Bucket-Wechsel neu geöffnet —
/// das verhindert Thrashing und spart Akku direkt auf Hardware-Ebene.
///
/// Lifecycle: [start] einmalig aufrufen; [dispose] beim Konvoi-Ende.
/// [stream] ist ein Broadcast-Stream — mehrere Listener sind sicher.
class GpsProducer {
  GpsProducer({
    required this.memberId,
    PositionStreamFactory streamFactory = defaultPositionStreamFactory,
    LocationSettingsFactory settingsFactory = defaultLocationSettingsFactory,
    Duration Function(GpsUpdate) intervalStrategy = adaptiveGpsInterval,
    void Function(Object, StackTrace)? onError,
  })  : _streamFactory = streamFactory,
        _settingsFactory = settingsFactory,
        _intervalStrategy = intervalStrategy,
        _onError = onError;

  final String memberId;
  final PositionStreamFactory _streamFactory;
  final LocationSettingsFactory _settingsFactory;
  final Duration Function(GpsUpdate) _intervalStrategy;
  final void Function(Object, StackTrace)? _onError;

  final _controller = StreamController<GpsUpdate>.broadcast();
  StreamSubscription<Position>? _positionSub;
  _Bucket _currentBucket = _Bucket.slow;
  bool _started = false;
  bool _disposed = false;
  bool _isBackground = false;
  bool _isLowBattery = false;

  /// True when any throttle override is active (background or low battery).
  bool get _forceSlow => _isBackground || _isLowBattery;

  /// Broadcast stream of tagged GPS updates. Safe to listen before [start].
  Stream<GpsUpdate> get stream => _controller.stream;

  /// Forces the slow bucket (5 s) while the app is backgrounded.
  set background(bool isBackground) {
    if (_isBackground == isBackground) return;
    _isBackground = isBackground;
    _applyThrottleMode();
  }

  /// Forces the slow bucket (5 s) when battery level drops below 20 %.
  /// Reverts to speed-adaptive sampling when battery recovers.
  set lowBattery(bool isLow) {
    if (_isLowBattery == isLow) return;
    _isLowBattery = isLow;
    _applyThrottleMode();
  }

  void _applyThrottleMode() {
    if (!_started || _disposed) return;
    if (_forceSlow) {
      if (_currentBucket != _Bucket.slow) _openStream(_Bucket.slow);
    } else {
      // Re-open so the stream restarts in full adaptive mode; next position
      // event promotes to the correct bucket.
      _openStream(_currentBucket);
    }
  }

  void start() {
    if (_disposed) throw StateError('GpsProducer already disposed');
    if (_started) return;
    _started = true;
    _openStream(_Bucket.slow);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _positionSub?.cancel();
    _positionSub = null;
    await _controller.close();
  }

  void _openStream(_Bucket bucket) {
    _positionSub?.cancel();
    _currentBucket = bucket;
    final settings =
        _settingsFactory(Duration(milliseconds: bucket.intervalMs));
    _positionSub = _streamFactory(settings).listen(
      _onPosition,
      onError: (Object e, StackTrace s) => _onError?.call(e, s),
      cancelOnError: false,
    );
  }

  void _onPosition(Position p) {
    if (_disposed) return;
    final update = GpsUpdate(
      memberId: memberId,
      latitude: p.latitude,
      longitude: p.longitude,
      headingDegrees: p.heading,
      speedMps: p.speed,
      timestamp: p.timestamp,
      accuracyMeters: p.accuracy,
    );
    _controller.add(update);
    if (!_forceSlow) {
      final newBucket = _Bucket.fromInterval(_intervalStrategy(update));
      if (newBucket != _currentBucket) {
        _openStream(newBucket);
      }
    }
  }
}

/// Default [LocationSettingsFactory]: platform-specific subclasses for
/// optimal battery usage. Falls back to base [LocationSettings] on
/// unsupported platforms.
LocationSettings defaultLocationSettingsFactory(Duration interval) {
  final ms = interval.inMilliseconds;
  final distFilter = ms >= 4000 ? 10 : ms >= 1500 ? 5 : 0;
  if (Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      intervalDuration: interval,
      distanceFilter: distFilter,
    );
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: distFilter,
      activityType: ActivityType.automotiveNavigation,
      pauseLocationUpdatesAutomatically: ms >= 4000,
    );
  }
  return LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: distFilter,
  );
}
