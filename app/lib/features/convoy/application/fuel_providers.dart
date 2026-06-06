import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/fuel_estimate.dart';

/// Driver's current tank level (0.0 … 1.0). Manual — the driver updates it.
/// Defaults to a full tank. Session-scoped (not persisted across restarts).
final fuelLevelProvider = StateProvider<double>((ref) => 1.0);

/// Vehicle range on a full tank, in km. Configurable per driver/vehicle.
final fuelRangeKmProvider = StateProvider<int>((ref) => 500);

/// Combined remaining-range estimate for the local driver.
final fuelEstimateProvider = Provider<FuelEstimate>((ref) {
  return FuelEstimate(
    level: ref.watch(fuelLevelProvider),
    rangeOnFullKm: ref.watch(fuelRangeKmProvider),
  );
});
