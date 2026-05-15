import 'package:crew_link/features/convoy/presentation/convoy_join_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({String? prefillCode}) => MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            key: const ValueKey('open'),
            onPressed: () => showModalBottomSheet<String>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => ConvoyJoinSheet(prefillCode: prefillCode),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

Future<String?> _openAndSubmit(
  WidgetTester tester, {
  String? prefillCode,
  String? enterCode,
}) async {
  String? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            key: const ValueKey('open'),
            onPressed: () async {
              result = await showModalBottomSheet<String>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => ConvoyJoinSheet(prefillCode: prefillCode),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  if (enterCode != null) {
    await tester.enterText(find.byType(TextField), enterCode);
  }
  await tester.tap(find.text('Beitreten'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('ConvoyJoinSheet', () {
    testWidgets('renders title, input and button', (tester) async {
      await tester.pumpWidget(_host());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();

      expect(find.text('Konvoi beitreten'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Beitreten'), findsOneWidget);
    });

    testWidgets('empty code keeps sheet open', (tester) async {
      await tester.pumpWidget(_host());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Beitreten'));
      await tester.pump();

      expect(find.text('Konvoi beitreten'), findsOneWidget);
    });

    testWidgets('entered code pops with that code', (tester) async {
      final result = await _openAndSubmit(tester, enterCode: 'XYZ789');

      expect(result, 'XYZ789');
    });

    testWidgets('prefillCode pre-fills the text field', (tester) async {
      await tester.pumpWidget(_host(prefillCode: 'PRE123'));
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();

      expect(find.descendant(
        of: find.byType(TextField),
        matching: find.text('PRE123'),
      ), findsOneWidget);
    });

    testWidgets('prefillCode pops immediately on Beitreten', (tester) async {
      final result = await _openAndSubmit(tester, prefillCode: 'PRE123');
      expect(result, 'PRE123');
    });
  });
}
