import 'package:geolocator/geolocator.dart';

/// Outcome of a location-readiness check/request.
enum LocationReadiness {
  /// Device location service on + foreground permission granted.
  ready,

  /// The device location/GPS toggle is OFF — no position stream is possible.
  serviceOff,

  /// Permission denied but can be asked again.
  denied,

  /// Permission permanently denied — the user must enable it in app settings.
  deniedForever,
}

/// Wraps the geolocator permission + service flow the GPS producer needs before
/// it can open a position stream.
///
/// Two entry points:
///  • [requestForConvoy] at app start (after the push prompt) — asks for the
///    foreground permission up front, even if GPS is momentarily off.
///  • [ensureReady] when entering a convoy / from the "activate location" CTA —
///    turns the device location service on (opens system settings if off),
///    requests the permission, and opens app settings if permanently denied.
///
/// All methods fail safe: if the geolocator platform channel is unavailable
/// (e.g. widget tests) they return a non-ready status instead of throwing.
class LocationPermissionService {
  const LocationPermissionService._();

  /// Requests FOREGROUND location permission if not yet decided. Does NOT touch
  /// the device location-service toggle — so the system dialog still appears at
  /// startup even when GPS happens to be off. Returns true when granted.
  static Future<bool> requestForConvoy() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Non-prompting status check — drives the in-convoy "no GPS" banner.
  static Future<LocationReadiness> status() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationReadiness.serviceOff;
      }
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        return LocationReadiness.deniedForever;
      }
      if (permission == LocationPermission.denied) {
        return LocationReadiness.denied;
      }
      return LocationReadiness.ready;
    } catch (_) {
      return LocationReadiness.serviceOff;
    }
  }

  /// Everything the live map needs: enables the device location service
  /// (opens the system location settings when it is off — this is the
  /// "activate location automatically" step), requests the foreground
  /// permission, and opens app settings when it was permanently denied.
  /// Call on convoy entry and from the "Standort aktivieren" CTA.
  static Future<LocationReadiness> ensureReady() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
        if (!await Geolocator.isLocationServiceEnabled()) {
          return LocationReadiness.serviceOff;
        }
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return LocationReadiness.deniedForever;
      }
      if (permission == LocationPermission.denied) {
        return LocationReadiness.denied;
      }
      return LocationReadiness.ready;
    } catch (_) {
      return LocationReadiness.serviceOff;
    }
  }

  /// Reports whether background ("Always") location is already granted.
  /// Deliberately does NOT auto-request the upgrade (Android 11+ would bounce
  /// to the settings page mid-flow); an explicit in-app prompt should drive it.
  static Future<bool> requestAlways() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// True when the app currently holds at least foreground location access.
  static Future<bool> hasPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }
}
