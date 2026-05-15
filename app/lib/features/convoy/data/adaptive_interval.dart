import 'dart:math' as math;

import '../../../core/models/gps_update.dart';

/// Speed-coupled GPS publish interval. Driving the throttle frequency
/// from the user's actual motion is the single biggest lever on the
/// "<8 % Akku pro Stunde aktiver Konvoi-Nutzung" goal: a parked phone
/// has no business uploading a fix every second.
///
/// Curve (km/h → interval):
///  - ≤ 5 km/h:   5 s (effectively stationary)
///  - 5..30 km/h: linear ramp 5 s → 1 s
///  - ≥ 30 km/h:  1 s (driving)
const double _msPerSecondToKmh = 3.6;
const double _slowKmh = 5;
const double _fastKmh = 30;
const Duration _slowInterval = Duration(seconds: 5);
const Duration _fastInterval = Duration(seconds: 1);

Duration adaptiveGpsInterval(GpsUpdate update) {
  final kmh = update.speedMps * _msPerSecondToKmh;
  if (kmh <= _slowKmh) return _slowInterval;
  if (kmh >= _fastKmh) return _fastInterval;
  final ratio = (kmh - _slowKmh) / (_fastKmh - _slowKmh);
  final ms = _slowInterval.inMilliseconds +
      ((_fastInterval.inMilliseconds - _slowInterval.inMilliseconds) * ratio)
          .round();
  return Duration(milliseconds: math.max(_fastInterval.inMilliseconds, ms));
}
