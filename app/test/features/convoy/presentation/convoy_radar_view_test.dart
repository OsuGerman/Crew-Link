import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/presentation/convoy_radar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GpsUpdate _u(String id, double lat, double lon) => GpsUpdate(
      memberId: id,
      latitude: lat,
      longitude: lon,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: DateTime.utc(2026, 5, 13, 12),
    );

Widget _harness({
  required String selfId,
  required Map<String, GpsUpdate> positions,
  double threshold = 500,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 320,
        height: 320,
        child: ConvoyRadarView(
          selfMemberId: selfId,
          positions: positions,
          thresholdMeters: threshold,
        ),
      ),
    ),
  );
}

void main() {
  group('ConvoyRadarView', () {
    testWidgets('renders without errors when self position is missing',
        (tester) async {
      await tester.pumpWidget(
        _harness(selfId: 'me', positions: const {}),
      );
      expect(find.byKey(const ValueKey('convoy-radar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders self + peers without throwing', (tester) async {
      final positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
        'peer-near': _u('peer-near', 52.5200, 13.4060), // ~78m east
        'peer-far': _u('peer-far', 52.5300, 13.4050), // ~1.1km north
      };
      await tester.pumpWidget(_harness(selfId: 'me', positions: positions));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('repaints when positions change', (tester) async {
      var positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
      };
      await tester.pumpWidget(_harness(selfId: 'me', positions: positions));

      positions = <String, GpsUpdate>{
        'me': _u('me', 52.5200, 13.4050),
        'peer': _u('peer', 52.5200, 13.4060),
      };
      await tester.pumpWidget(_harness(selfId: 'me', positions: positions));
      expect(tester.takeException(), isNull);
    });
  });
}
