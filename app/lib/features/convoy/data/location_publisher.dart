import 'dart:async';

import '../../../core/models/gps_update.dart';

/// Sink callback used by [LocationPublisher] to forward a position
/// upstream — typically `ConvoySocketClient.publishLocation`.
typedef LocationSink = void Function(GpsUpdate update);

/// Strategy that picks the minimum interval between sink emissions
/// for a given update. Letting this depend on the update itself is
/// the seam that the adaptive-speed strategy in
/// `data/adaptive_interval.dart` plugs into.
typedef IntervalStrategy = Duration Function(GpsUpdate update);

/// Bridges a local device location stream into the convoy WebSocket
/// channel. The publisher itself is transport-agnostic: it consumes a
/// [Stream<GpsUpdate>] and forwards each tick via [LocationSink].
///
/// Rate-limit: emissions to [sink] are throttled to at most one update
/// per [minInterval]. The most recent position is always preserved —
/// when an in-flight throttle window closes, the latest skipped update
/// is flushed so consumers never get stuck on a stale position.
///
/// Errors from [source] are swallowed (logged via [onError] if given)
/// rather than re-thrown — a transient GPS failure must not tear down
/// the whole convoy session.
class LocationPublisher {
  LocationPublisher({
    required Stream<GpsUpdate> source,
    required LocationSink sink,
    Duration minInterval = const Duration(seconds: 1),
    IntervalStrategy? intervalStrategy,
    void Function(Object error, StackTrace stack)? onError,
    DateTime Function()? clock,
  })  : _source = source,
        _sink = sink,
        _minInterval = minInterval,
        _intervalStrategy = intervalStrategy,
        _onError = onError,
        _clock = clock ?? DateTime.now;

  final Stream<GpsUpdate> _source;
  final LocationSink _sink;
  final Duration _minInterval;
  final IntervalStrategy? _intervalStrategy;
  final void Function(Object, StackTrace)? _onError;
  final DateTime Function() _clock;

  Duration _intervalFor(GpsUpdate update) =>
      _intervalStrategy?.call(update) ?? _minInterval;

  StreamSubscription<GpsUpdate>? _sub;
  DateTime? _lastEmitAt;
  GpsUpdate? _pendingFlush;
  Timer? _flushTimer;
  bool _disposed = false;

  bool get isRunning => _sub != null;

  void start() {
    if (_disposed) {
      throw StateError('LocationPublisher already disposed');
    }
    if (_sub != null) {
      return;
    }
    _sub = _source.listen(
      _onUpdate,
      onError: (Object e, StackTrace s) => _onError?.call(e, s),
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingFlush = null;
    _lastEmitAt = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }

  void _onUpdate(GpsUpdate update) {
    final now = _clock();
    final last = _lastEmitAt;
    final interval = _intervalFor(update);
    if (last == null || now.difference(last) >= interval) {
      _emit(update, now);
      return;
    }
    _pendingFlush = update;
    _flushTimer ??= Timer(interval - now.difference(last), _flushPending);
  }

  void _flushPending() {
    _flushTimer = null;
    final pending = _pendingFlush;
    _pendingFlush = null;
    if (pending == null || _disposed || _sub == null) {
      return;
    }
    _emit(pending, _clock());
  }

  void _emit(GpsUpdate update, DateTime at) {
    // Update _lastEmitAt only on success. If the sink throws (e.g. an
    // unrecoverable transport error in a future PTT pipeline), do NOT
    // burn the throttle window on a failed send — the next incoming
    // tick should be eligible to emit immediately.
    try {
      _sink(update);
      _lastEmitAt = at;
    } catch (e, s) {
      _onError?.call(e, s);
    }
  }
}
