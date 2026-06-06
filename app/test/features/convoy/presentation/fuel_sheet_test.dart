import 'package:crew_link/features/convoy/application/fuel_providers.dart';
import 'package:crew_link/features/convoy/presentation/fuel_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: Scaffold(body: FuelSheet())),
    );

String _remaining(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('fuel-remaining'))).data!;

void main() {
  group('FuelSheet', () {
    testWidgets('shows remaining range and no warning when full',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(_remaining(tester), contains('500 km'));
      expect(find.byKey(const ValueKey('fuel-warning')), findsNothing);
    });

    testWidgets('low level shows the warning', (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: [fuelLevelProvider.overrideWith((ref) => 0.1)],
      ));
      expect(_remaining(tester), contains('50 km'));
      expect(find.byKey(const ValueKey('fuel-warning')), findsOneWidget);
    });

    testWidgets('range stepper raises the range on a full tank',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.byKey(const ValueKey('fuel-range-plus')));
      await tester.pump();
      expect(_remaining(tester), contains('550 km'));
    });
  });
}
