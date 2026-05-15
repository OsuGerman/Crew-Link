import 'package:geolocator/geolocator.dart';

/// Wraps the two-step geolocator permission flow required before the GPS
/// producer can open a position stream.
///
/// Call [requestForConvoy] once at app start. On iOS the system shows the
/// "While In Use" dialog on first call; Android shows "Precise Location".
/// Background permission ([LocationPermission.always]) is requested
/// separately in [requestAlways] and only after foreground is granted —
/// Apple App Store and Google Play policies require this two-step approach.
class LocationPermissionService {
  const LocationPermissionService._();

  /// Requests foreground location permission if not already granted.
  /// Returns `true` when the app may access location (while in use or always).
  static Future<bool> requestForConvoy() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Upgrades foreground permission to "Always" for background tracking.
  /// Must only be called after [requestForConvoy] has returned `true`.
  /// Returns `true` if background access was granted.
  static Future<bool> requestAlways() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) return true;
    if (permission != LocationPermission.whileInUse) return false;
    permission = await Geolocator.requestPermission();
    return permission == LocationPermission.always;
  }

  /// True when the app currently holds at least foreground location access.
  static Future<bool> hasPermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }
}
