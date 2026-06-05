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

  /// Reports whether background ("Always") location is already granted.
  ///
  /// Deliberately does NOT auto-request the upgrade: on Android 11+ requesting
  /// background access bounces the user to the system settings page, which is
  /// jarring mid-flow (e.g. right after creating a convoy). The upgrade should
  /// be driven by an explicit in-app prompt. Foreground ("While in use") access
  /// from [requestForConvoy] is enough for the live map while the app is open.
  static Future<bool> requestAlways() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  /// True when the app currently holds at least foreground location access.
  static Future<bool> hasPermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }
}
