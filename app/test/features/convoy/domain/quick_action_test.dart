import 'package:crew_link/features/convoy/domain/quick_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuickAction', () {
    test('wireValue maps each kind to the backend enum string', () {
      expect(QuickActionKind.pause.wireValue, 'pause');
      expect(QuickActionKind.fuelStop.wireValue, 'fuel_stop');
      expect(QuickActionKind.backInConvoy.wireValue, 'back_in_convoy');
      expect(QuickActionKind.vehicleProblem.wireValue, 'vehicle_problem');
    });

    test('fromWire round-trips every kind', () {
      for (final k in QuickActionKind.values) {
        expect(QuickActionKind.fromWire(k.wireValue), k);
      }
    });

    test('fromWire falls back to pause for unknown values', () {
      expect(QuickActionKind.fromWire('nope'), QuickActionKind.pause);
    });

    test('toJson/fromJson round-trips', () {
      final action = QuickAction(
        memberId: 'm1',
        kind: QuickActionKind.fuelStop,
        at: DateTime.utc(2026, 6, 6, 12, 30),
      );
      final restored = QuickAction.fromJson(action.toJson());
      expect(restored.memberId, 'm1');
      expect(restored.kind, QuickActionKind.fuelStop);
      expect(restored.at, action.at);
    });
  });
}
