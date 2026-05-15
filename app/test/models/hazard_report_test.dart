import 'package:crew_link/core/models/hazard_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HazardType', () {
    test('round-trips wire values for all variants', () {
      for (final type in HazardType.values) {
        expect(HazardType.fromWire(type.wireValue), type);
      }
    });

    test('unknown wire value falls back to other', () {
      expect(HazardType.fromWire('lava-flow'), HazardType.other);
    });
  });

  group('HazardReport', () {
    final base = HazardReport(
      id: 'hz-1',
      type: HazardType.construction,
      latitude: 49.4521,
      longitude: 11.0767,
      reporterId: 'driver-7',
      createdAt: DateTime.utc(2026, 5, 14, 12, 30),
      convoyId: 'cv-42',
      description: 'Rechte Spur gesperrt',
      expiresAt: DateTime.utc(2026, 5, 14, 14, 30),
    );

    test('round-trips JSON with all fields', () {
      final decoded = HazardReport.fromJson(base.toJson());

      expect(decoded, base);
    });

    test('round-trips JSON when optionals are null', () {
      final minimal = HazardReport(
        id: 'hz-2',
        type: HazardType.poorVisibility,
        latitude: 0,
        longitude: 0,
        reporterId: 'driver-1',
        createdAt: DateTime.utc(2026),
      );

      final json = minimal.toJson();
      expect(json.containsKey('convoyId'), isFalse);
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('expiresAt'), isFalse);

      expect(HazardReport.fromJson(json), minimal);
    });

    test('toPostBody strips id, createdAt, reporterId and empty strings', () {
      final draft = base.copyWith(description: '   ');
      final body = draft.toPostBody();

      expect(body.containsKey('id'), isFalse);
      expect(body.containsKey('createdAt'), isFalse);
      expect(body.containsKey('reporterId'), isFalse);
      expect(body.containsKey('description'), isFalse,
          reason: 'whitespace-only description darf nicht gepostet werden');
      expect(body['type'], 'construction');
      expect(body['latitude'], 49.4521);
      expect(body['longitude'], 11.0767);
      expect(body['convoyId'], 'cv-42');
      expect(body['expiresAt'], '2026-05-14T14:30:00.000Z');
    });

    test('isActiveAt is true before expiry and false after', () {
      expect(
        base.isActiveAt(DateTime.utc(2026, 5, 14, 13)),
        isTrue,
      );
      expect(
        base.isActiveAt(DateTime.utc(2026, 5, 14, 15)),
        isFalse,
      );
    });

    test('isActiveAt without expiry is always true', () {
      final permanent = HazardReport(
        id: 'hz-3',
        type: HazardType.obstacle,
        latitude: 0,
        longitude: 0,
        reporterId: 'driver-9',
        createdAt: DateTime.utc(2026),
      );

      expect(
        permanent.isActiveAt(DateTime.utc(2099, 12, 31)),
        isTrue,
      );
    });

    test('police_checkpoint serialises with underscored wire value', () {
      final report = base.copyWith(type: HazardType.policeCheckpoint);
      expect(report.toJson()['type'], 'police_checkpoint');
    });
  });
}
