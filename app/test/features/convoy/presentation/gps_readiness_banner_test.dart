import 'package:crew_link/features/convoy/presentation/gps_readiness_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping Aktivieren fires onActivate', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GpsReadinessBanner(onActivate: () => taps++),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('gps-readiness-banner')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gps-activate-button')));
    await tester.pump();
    expect(taps, 1);
  });
}
