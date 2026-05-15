import 'package:geolocator/geolocator.dart';

import '../../../core/models/gps_update.dart';

/// Factory that opens a device-level position stream. Indirected through a
/// typedef so unit tests can inject a fake without touching the geolocator
/// plugin (which talks to platform channels and is unavailable in `flutter
/// test`).
typedef PositionStreamFactory = Stream<Position> Function(
  LocationSettings settings,
);

/// Default position-stream factory: the real geolocator plugin. Kept as a
/// top-level function so it can be tree-shaken out when tests override it.
Stream<Position> defaultPositionStreamFactory(LocationSettings settings) =>
    Geolocator.getPositionStream(locationSettings: settings);

/// Adapts the platform GPS stream into a [Stream<GpsUpdate>] tagged with
/// the local member id, ready to feed [LocationPublisher].
///
/// Rule: GPS updates flow exclusively over the convoy WebSocket — this
/// adapter only produces the typed update; transport is owned by
/// [LocationPublisher] / [ConvoySocketClient]. Polling is not used; the
/// underlying geolocator stream is event-driven.
class PlatformLocationAdapter {
  PlatformLocationAdapter({
    required this.memberId,
    LocationSettings? settings,
    PositionStreamFactory factory = defaultPositionStreamFactory,
  })  : _settings = settings ??
            const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
            ),
        _factory = factory;

  final String memberId;
  final LocationSettings _settings;
  final PositionStreamFactory _factory;

  Stream<GpsUpdate> stream() {
    return _factory(_settings).map(_toUpdate);
  }

  GpsUpdate _toUpdate(Position p) => GpsUpdate(
        memberId: memberId,
        latitude: p.latitude,
        longitude: p.longitude,
        headingDegrees: p.heading,
        speedMps: p.speed,
        timestamp: p.timestamp,
        accuracyMeters: p.accuracy,
      );
}
