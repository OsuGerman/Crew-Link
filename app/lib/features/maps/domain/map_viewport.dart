import 'package:latlong2/latlong.dart';

/// Sichtbarer Kartenausschnitt mit Mittelpunkt und Zoom-Level.
class MapViewport {
  const MapViewport({
    required this.centerLat,
    required this.centerLng,
    required this.zoomLevel,
  });

  final double centerLat;
  final double centerLng;
  final double zoomLevel;

  LatLng get center => LatLng(centerLat, centerLng);

  static const double _defaultZoom = 14.0;
  static const double _paddingFactor = 1.4;

  /// Computes a viewport that fits all given positions with padding.
  /// Falls back to Munich city center at zoom 12 when [positions] is empty.
  factory MapViewport.fitPositions(
    List<({double lat, double lng})> positions,
  ) {
    if (positions.isEmpty) {
      return const MapViewport(
        centerLat: 48.137,
        centerLng: 11.575,
        zoomLevel: 12,
      );
    }
    if (positions.length == 1) {
      return MapViewport(
        centerLat: positions.first.lat,
        centerLng: positions.first.lng,
        zoomLevel: _defaultZoom,
      );
    }

    final lats = positions.map((p) => p.lat);
    final lngs = positions.map((p) => p.lng);
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    final latSpan = (maxLat - minLat) * _paddingFactor;
    final lngSpan = (maxLng - minLng) * _paddingFactor;
    final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;

    final zoom = switch (maxSpan) {
      <= 0.002 => 17.0,
      <= 0.01 => 15.0,
      <= 0.05 => 13.0,
      <= 0.1 => 12.0,
      <= 0.5 => 10.0,
      <= 2.0 => 8.0,
      _ => 6.0,
    };

    return MapViewport(
      centerLat: centerLat,
      centerLng: centerLng,
      zoomLevel: zoom,
    );
  }
}
