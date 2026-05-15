import 'package:crew_link/features/beta/application/beta_feedback_provider.dart';
import 'package:crew_link/features/beta/domain/beta_feedback.dart';
import 'package:crew_link/features/beta/presentation/beta_feedback_sheet.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFeedbackNotifier extends BetaFeedbackNotifier {
  _FakeFeedbackNotifier() : super(userId: 'test-user', firestore: null);

  bool submitCalled = false;
  FeedbackCategory? lastCategory;
  String? lastMessage;

  @override
  Future<void> submit({
    required FeedbackCategory category,
    required String message,
    required String buildVersion,
    String screenContext = '',
  }) async {
    submitCalled = true;
    lastCategory = category;
    lastMessage = message;
    state = FeedbackSubmitState.success;
  }
}

Widget _wrap(Widget child, {BetaFeedbackNotifier? notifier}) {
  return ProviderScope(
    overrides: [
      selfMemberIdProvider.overrideWithValue('test-user'),
      if (notifier != null)
        betaFeedbackProvider
            .overrideWith((_) => notifier),
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('BetaFeedbackSheet', () {
    testWidgets('renders category dropdown and message field', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => BetaFeedbackSheet.show(context),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Beta-Feedback'), findsOneWidget);
      expect(find.text('Kategorie'), findsOneWidget);
      expect(find.text('Beschreibung'), findsOneWidget);
      expect(find.text('Feedback senden'), findsOneWidget);
    });

    testWidgets('submit button calls notifier.submit with entered message',
        (tester) async {
      final notifier = _FakeFeedbackNotifier();

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => BetaFeedbackSheet.show(context),
              child: const Text('Open'),
            ),
          ),
          notifier: notifier,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'GPS verliert Position');
      await tester.tap(find.text('Feedback senden'));
      await tester.pumpAndSettle();

      expect(notifier.submitCalled, isTrue);
      expect(notifier.lastMessage, 'GPS verliert Position');
    });

    testWidgets('shows SnackBar on success and closes sheet', (tester) async {
      final notifier = _FakeFeedbackNotifier();

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => BetaFeedbackSheet.show(context),
              child: const Text('Open'),
            ),
          ),
          notifier: notifier,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Guter Hinweis');
      await tester.tap(find.text('Feedback senden'));
      await tester.pumpAndSettle();

      expect(find.text('Feedback gesendet — danke!'), findsOneWidget);
      expect(find.text('Beta-Feedback'), findsNothing);
    });
  });
}
