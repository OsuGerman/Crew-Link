import 'package:crew_link/features/auth/application/auth_providers.dart';
import 'package:crew_link/features/auth/presentation/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app() => ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: const MaterialApp(home: AccountScreen()),
    );

void main() {
  group('AccountScreen', () {
    testWidgets('shows sign-out and delete-account actions', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();

      expect(find.byKey(const ValueKey('sign-out-button')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('delete-account-button')), findsOneWidget);
    });

    testWidgets('delete tap shows an irreversible confirmation', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('delete-account-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('confirm-delete-account')),
          findsOneWidget);
      expect(find.textContaining('unwiderruflich'), findsOneWidget);
    });
  });
}
