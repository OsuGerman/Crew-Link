/// Range bucket for the driver's current fuel level — drives the colour and
/// the low-fuel warning in the fuel sheet.
enum FuelTier { ok, low, critical }

/// Pure estimate of remaining range from a manual tank level and the vehicle's
/// range on a full tank. No automatic decrement — the driver updates the level.
class FuelEstimate {
  const FuelEstimate({required this.level, required this.rangeOnFullKm});

  /// Tank level, 0.0 (empty) … 1.0 (full).
  final double level;

  /// How far the vehicle goes on a full tank, in km.
  final int rangeOnFullKm;

  /// Estimated remaining range in km.
  int get remainingKm => (level.clamp(0.0, 1.0) * rangeOnFullKm).round();

  FuelTier get tier {
    final km = remainingKm;
    if (km <= 30) return FuelTier.critical;
    if (km <= 80) return FuelTier.low;
    return FuelTier.ok;
  }

  /// Whether the convoy should be warned (low or critical).
  bool get shouldWarn => tier != FuelTier.ok;
}
