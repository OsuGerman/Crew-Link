import 'dart:convert';

import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/presentation/deep_link_join_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _fakeConvoyJson({String invite = 'ABC123'}) => {
      'id': 'c1',
      'name': 'Trip',
      'inviteCode': invite,
      'members': <Object?>[],
      'proximityWarningMeters': 500,
      'createdAt': '2026-05-13T12:00:00Z',
    };

Widget _wrap({
  required String inviteCode,
  required http.Client client,
}) {
  final router = GoRouter(
    initialLocation: '/join/$inviteCode',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/join/:code',
        builder: (_, state) =>
            DeepLinkJoinScreen(inviteCode: state.pathParameters['code']!),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      httpClientProvider.overrideWithValue(client),
      authTokenProvider.overrideWithValue('test-token'),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('DeepLinkJoinScreen', () {
    testWidgets('shows invite code and join button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          inviteCode: 'ABC123',
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Einladung'), findsOneWidget);
      expect(find.text('Code: ABC123'), findsOneWidget);
      expect(find.text('Jetzt beitreten'), findsOneWidget);
    });

    testWidgets('successful join navigates to home', (tester) async {
      await tester.pumpWidget(
        _wrap(
          inviteCode: 'ABC123',
          client: MockClient(
            (_) async =>
                http.Response(jsonEncode(_fakeConvoyJson(invite: 'ABC123')), 200),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jetzt beitreten'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('API failure shows error snackbar', (tester) async {
      await tester.pumpWidget(
        _wrap(
          inviteCode: 'BAD',
          client: MockClient(
            (_) async => http.Response('not found', 404),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jetzt beitreten'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Fehler'), findsOneWidget);
      expect(find.text('Jetzt beitreten'), findsOneWidget);
    });

    testWidgets('Abbrechen navigates to home', (tester) async {
      await tester.pumpWidget(
        _wrap(
          inviteCode: 'ABC123',
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });
  });
}
