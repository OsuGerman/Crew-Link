import 'package:crew_link/features/convoy/presentation/convoy_create_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host() => MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            key: const ValueKey('open'),
            onPressed: () => showModalBottomSheet<CreateConvoyResult>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => const ConvoyCreateSheet(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

Future<CreateConvoyResult?> _runFullFlow(
  WidgetTester tester, {
  String name = 'Alpha Run',
  double threshold = 500,
}) async {
  CreateConvoyResult? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            key: const ValueKey('open'),
            onPressed: () async {
              result = await showModalBottomSheet<CreateConvoyResult>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => const ConvoyCreateSheet(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await _openSheet(tester);

  // Step 1 — Name eingeben + Weiter
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('convoy-create-step0-btn')));
  await tester.pumpAndSettle();

  // Step 2 — Schwellenwert wählen (sofern nicht Standard 500m) + Weiter
  if (threshold != 500) {
    await tester.tap(
      find.byKey(ValueKey('threshold-chip-${threshold.toInt()}')),
    );
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey('convoy-create-step1-btn')));
  await tester.pumpAndSettle();

  // Step 3 — Erstellen
  await tester.tap(find.byKey(const ValueKey('convoy-create-step2-btn')));
  await tester.pumpAndSettle();

  return result;
}

void main() {
  group('ConvoyCreateSheet', () {
    testWidgets('step 1 — zeigt Titel, Textfeld und Weiter-Button',
        (tester) async {
      await tester.pumpWidget(_host());
      await _openSheet(tester);

      expect(find.text('Konvoi erstellen'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Weiter'), findsOneWidget);
    });

    testWidgets('step 1 — Weiter deaktiviert bei leerem Namen', (tester) async {
      await tester.pumpWidget(_host());
      await _openSheet(tester);

      final btn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('convoy-create-step0-btn')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('step 1 — Weiter aktiviert nach Namenseingabe', (tester) async {
      await tester.pumpWidget(_host());
      await _openSheet(tester);

      await tester.enterText(find.byType(TextField), 'Beta Run');
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('convoy-create-step0-btn')),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('step 1 — nur Leerzeichen deaktiviert Weiter', (tester) async {
      await tester.pumpWidget(_host());
      await _openSheet(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('convoy-create-step0-btn')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('step 1 → 2 — Weiter navigiert zu Warnabstand', (tester) async {
      await tester.pumpWidget(_host());
      await _openSheet(tester);

      await tester.enterText(find.byType(TextField), 'Gamma Run');
      await tester.tap(find.byKey(const ValueKey('convoy-create-step0-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Warnabstand'), findsWidgets);
      expect(find.byKey(const ValueKey('threshold-chip-300')), findsOneWidget);
      expect(find.byKey(const ValueKey('threshold-chip-500')), findsOneWidget);
      expect(find.byKey(const ValueKey('threshold-chip-1000')), findsOneWidget);
    });

    testWidgets('step 2 → 3 — zeigt Name und Schwellenwert in Zusammenfassung',
        (tester) async {
      await tester.pumpWidget(_host());
      await _openSheet(tester);

      await tester.enterText(find.byType(TextField), 'Delta Run');
      await tester.tap(find.byKey(const ValueKey('convoy-create-step0-btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('convoy-create-step1-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Zusammenfassung'), findsOneWidget);
      expect(find.text('Delta Run'), findsOneWidget);
      // '500 m' kann in Chip + Confirm-Row doppelt vorkommen → findsWidgets
      expect(find.text('500 m'), findsWidgets);
      expect(find.text('Erstellen'), findsOneWidget);
    });

    testWidgets('vollständiger Flow popt mit Standard-500m', (tester) async {
      final result = await _runFullFlow(tester, name: 'Alpha Run');

      expect(result, isNotNull);
      expect(result!.name, 'Alpha Run');
      expect(result.thresholdMeters, 500.0);
    });

    testWidgets('threshold 300 m wird übernommen', (tester) async {
      final result =
          await _runFullFlow(tester, name: 'Bravo Run', threshold: 300);

      expect(result?.thresholdMeters, 300.0);
    });

    testWidgets('threshold 1 km wird übernommen', (tester) async {
      final result =
          await _runFullFlow(tester, name: 'Charlie Run', threshold: 1000);

      expect(result?.thresholdMeters, 1000.0);
      // confirm step shows "1 km" label
    });
  });
}
