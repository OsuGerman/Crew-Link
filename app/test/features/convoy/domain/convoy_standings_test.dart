import 'package:crew_link/core/models/convoy_member.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/domain/convoy_standings.dart';
import 'package:flutter_test/flutter_test.dart';

ConvoyMember _m(String id, {bool leader = false}) =>
    ConvoyMember(id: id, displayName: id, isLeader: leader);

GpsUpdate _p(String id, double lat, double lng) => GpsUpdate(
      memberId: id,
      latitude: lat,
      longitude: lng,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: DateTime.utc(2026),
    );

void main() {
  group('computeConvoyStandings', () {
    final members = [_m('leader', leader: true), _m('b'), _m('d'), _m('c')];

    test('leader is #1 + green; others ranked and bucketed by gap', () {
      final positions = {
        'leader': _p('leader', 48.0, 11.0),
        'b': _p('b', 48.0, 11.001), // ~74 m  -> green
        'd': _p('d', 48.0, 11.005), // ~372 m -> yellow
        'c': _p('c', 48.0, 11.010), // ~744 m -> red
      };
      final s = computeConvoyStandings(
        members: members,
        positions: positions,
        thresholdMeters: 500,
      );

      expect(s['leader']!.ordinal, 1);
      expect(s['leader']!.tier, GapTier.green);
      expect(s['leader']!.gapMeters, isNull);

      expect(s['b']!.ordinal, 2);
      expect(s['b']!.tier, GapTier.green);

      expect(s['d']!.ordinal, 3);
      expect(s['d']!.tier, GapTier.yellow);

      expect(s['c']!.ordinal, 4);
      expect(s['c']!.tier, GapTier.red);
      expect(s['c']!.gapMeters, greaterThan(500));
    });

    test('members without a live position get no standing', () {
      final positions = {'leader': _p('leader', 48.0, 11.0)};
      final s = computeConvoyStandings(
        members: members,
        positions: positions,
        thresholdMeters: 500,
      );
      expect(s.keys.toList(), ['leader']);
      expect(s['b'], isNull);
    });

    test('no leader position → ranked but all green (no reference)', () {
      final positions = {
        'b': _p('b', 48.0, 11.001),
        'c': _p('c', 48.0, 11.010),
      };
      final s = computeConvoyStandings(
        members: members,
        positions: positions,
        thresholdMeters: 500,
      );
      expect(s['b']!.tier, GapTier.green);
      expect(s['c']!.tier, GapTier.green);
      expect(s['b']!.gapMeters, isNull);
    });
  });
}
