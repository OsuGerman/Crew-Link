import 'package:crew_link/features/convoy/domain/fuel_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FuelEstimate', () {
    test('remainingKm scales level by range on full', () {
      expect(
        const FuelEstimate(level: 0.5, rangeOnFullKm: 500).remainingKm,
        250,
      );
      expect(
        const FuelEstimate(level: 1.0, rangeOnFullKm: 480).remainingKm,
        480,
      );
    });

    test('level is clamped to 0..1', () {
      expect(
        const FuelEstimate(level: 1.4, rangeOnFullKm: 500).remainingKm,
        500,
      );
      expect(
        const FuelEstimate(level: -0.2, rangeOnFullKm: 500).remainingKm,
        0,
      );
    });

    test('tiers bucket by remaining range', () {
      // 500 km full → 0.05=25 km critical, 0.12=60 km low, 0.5=250 km ok.
      expect(
        const FuelEstimate(level: 0.05, rangeOnFullKm: 500).tier,
        FuelTier.critical,
      );
      expect(
        const FuelEstimate(level: 0.12, rangeOnFullKm: 500).tier,
        FuelTier.low,
      );
      expect(
        const FuelEstimate(level: 0.5, rangeOnFullKm: 500).tier,
        FuelTier.ok,
      );
    });

    test('shouldWarn is true only for low/critical', () {
      expect(
        const FuelEstimate(level: 0.5, rangeOnFullKm: 500).shouldWarn,
        isFalse,
      );
      expect(
        const FuelEstimate(level: 0.1, rangeOnFullKm: 500).shouldWarn,
        isTrue,
      );
    });
  });
}
