import 'package:crew_link/features/convoy/presentation/leader_route_cta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap({required VoidCallback onPlanRoute}) => MaterialApp(
      home: Scaffold(body: LeaderRouteCta(onPlanRoute: onPlanRoute)),
    );

void main() {
  group('LeaderRouteCta', () {
    testWidgets('renders the route-planning call-to-action', (tester) async {
      await tester.pumpWidget(_wrap(onPlanRoute: () {}));
      expect(find.byKey(const ValueKey('leader-route-cta')), findsOneWidget);
      expect(find.text('Ziel setzen · Route planen'), findsOneWidget);
    });

    testWidgets('tapping invokes the onPlanRoute callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(onPlanRoute: () => taps++));
      await tester.tap(find.byKey(const ValueKey('leader-route-cta')));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
