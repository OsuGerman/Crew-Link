import 'package:flutter/foundation.dart';

/// A single forward-geocoding match: a human-readable place label and its
/// coordinates. Used to turn an address/place search into a route waypoint.
@immutable
class GeocodeResult {
  const GeocodeResult({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;

  /// The leading, most-specific part of the label (e.g. street / place name)
  /// — a compact stop title for the route list.
  String get shortLabel {
    final head = label.split(',').first.trim();
    return head.isEmpty ? label : head;
  }
}
