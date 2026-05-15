import 'package:crew_link/core/models/vehicle_mod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VehicleMod', () {
    test('fromJson with all fields', () {
      final m = VehicleMod.fromJson(const {
        'id': 'm1',
        'name': 'Sport-Spoiler',
        'description': 'Carbon',
        'category': 'exterior',
      });
      expect(m.id, 'm1');
      expect(m.name, 'Sport-Spoiler');
      expect(m.description, 'Carbon');
      expect(m.category, 'exterior');
    });

    test('fromJson tolerates missing optional fields', () {
      final m = VehicleMod.fromJson(const {
        'id': 'm2',
        'name': 'Roll-Cage',
      });
      expect(m.description, isNull);
      expect(m.category, isNull);
    });

    test('toPutBody strips id and empty optionals', () {
      const m = VehicleMod(
        id: 'draft-123',
        name: 'Lowered',
        description: '',
        category: null,
      );
      final body = m.toPutBody();
      expect(body, {'name': 'Lowered'});
    });

    test('toPutBody keeps populated optionals', () {
      const m = VehicleMod(
        id: 'm3',
        name: 'Carbon-Wing',
        description: 'Adjustable',
        category: 'exterior',
      );
      final body = m.toPutBody();
      expect(body, {
        'name': 'Carbon-Wing',
        'description': 'Adjustable',
        'category': 'exterior',
      });
    });

    test('copyWith preserves id', () {
      const m = VehicleMod(id: 'm', name: 'A', category: 'wheels');
      final updated = m.copyWith(name: 'B');
      expect(updated.id, 'm');
      expect(updated.name, 'B');
      expect(updated.category, 'wheels');
    });

    test('equality compares all fields', () {
      const a = VehicleMod(id: '1', name: 'X', category: 'engine');
      const b = VehicleMod(id: '1', name: 'X', category: 'engine');
      const c = VehicleMod(id: '1', name: 'Y', category: 'engine');
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });
  });
}
