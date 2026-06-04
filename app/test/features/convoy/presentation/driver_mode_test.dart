import 'dart:async';
import 'dart:convert';

import 'package:crew_link/features/convoy/presentation/convoy_home_screen.dart';
import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/realtime/connection_status.dart';
import 'package:crew_link/core/realtime/convoy_socket_client.dart';
import 'package:crew_link/features/auth/application/auth_providers.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/application/driver_mode.dart';
import 'package:crew_link/features/onboarding/application/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../support/active_view_test_overrides.dart';

class _FakeSocket extends ConvoySocketClient {
  _FakeSocket({required super.convoyId})
      : super(config: ApiConfig.local(), authToken: 'tok');

  final _ctrl = StreamController<GpsUpdate>.broadcast();

  @override
  Stream<GpsUpdate> get gpsUpdates => _ctrl.stream;

  @override
  ConnectionStatus get currentStatus => ConnectionStatus.connected;

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      Stream<ConnectionStatus>.value(ConnectionStatus.connected);

  @override
  Future<void> connect() async {}

  @override
  void publishLocation(GpsUpdate update) => _ctrl.add(update);

  @override
  Future<void> disconnect() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}

http.Client _alwaysOkClient() => MockClient((req) async {
      return http.Response(
        jsonEncode({
          'id': 'c1',
          'name': 'Trip',
          'inviteCode': 'XYZ123',
          'members': const <Object?>[],
          'proximityWarningMeters': 500,
          'createdAt': '2026-05-13T12:00:00Z',
        }),
        200,
      );
    });

Widget _app({_FakeSocket? socket}) {
  return ProviderScope(
    overrides: [
      httpClientProvider.overrideWithValue(_alwaysOkClient()),
      authTokenProvider.overrideWithValue('test-token'),
      selfMemberIdProvider.overrideWithValue('self'),
      // Firebase is not initialized in widget tests, so authStateProvider
      // would error and the router would redirect to /login. Resolve auth to
      // a null user and flip the dev-signed-in override so the router's
      // auth gate passes and the ConvoyHomeScreen lobby renders.
      authStateProvider.overrideWith((ref) => Stream.value(null)),
      devSignedInOverrideProvider.overrideWith((ref) => true),
      onboardingCompletedProvider.overrideWith((ref) => true),
      // Pin the proximity-service clock so the synthetic GPS timestamps
      // in the proximity test don't trip the stale-position filter.
      clockProvider.overrideWithValue(
        () => DateTime.utc(2026, 5, 13, 12, 0, 30),
      ),
      convoySocketFactoryProvider.overrideWithValue(
        ({required convoyId, required authToken}) =>
            socket ?? _FakeSocket(convoyId: convoyId),
      ),
      ...activeViewStubOverrides(),
    ],
    // Render the screen directly (not the full CrewLinkApp): the production
    // GoRouter gates routes behind async auth/onboarding state that never
    // settles deterministically in a widget test. ConvoyHomeScreen renders
    // the lobby synchronously when there is no active convoy.
    child: const MaterialApp(home: ConvoyHomeScreen()),
  );
}

// ActiveConvoyView runs a continuous radar-sweep animation, so pumpAndSettle
// never completes once the active view is shown. Pump a bounded amount instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _enterActiveConvoy(WidgetTester tester) async {
  await tester.tap(find.text('Neuen Konvoi starten'));
  await tester.pumpAndSettle();
  // ConvoyCreateSheet is a 3-step wizard: name -> threshold -> confirm.
  await tester.enterText(find.byType(TextField), 'Trip');
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('convoy-create-step0-btn')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('convoy-create-step1-btn')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('convoy-create-step2-btn')));
  await tester.pumpAndSettle();
}

void main() {
  group('Driver-Mode toggle', () {
    testWidgets('toggle button is hidden in lobby, shown in active convoy',
        (tester) async {
      await tester.pumpWidget(_app());
      expect(find.byKey(const ValueKey('toggle-driver-mode')), findsNothing);

      await _enterActiveConvoy(tester);
      expect(find.byKey(const ValueKey('toggle-driver-mode')), findsOneWidget);
    });

    testWidgets('tapping the toggle swaps to the simplified view',
        (tester) async {
      await tester.pumpWidget(_app());
      await _enterActiveConvoy(tester);

      // Normal view: live-members-tile present, driver-leave-button absent.
      expect(find.byKey(const ValueKey('live-members-tile')), findsOneWidget);
      expect(find.byKey(const ValueKey('driver-leave-button')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('toggle-driver-mode')));
      await _settle(tester);

      // Driver view: simplified members summary + big leave button.
      expect(find.byKey(const ValueKey('driver-leave-button')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('driver-members-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-members-tile')), findsNothing);
    });

    testWidgets('vehicle-profile icon is hidden in driver-mode',
        (tester) async {
      await tester.pumpWidget(_app());
      await _enterActiveConvoy(tester);
      expect(find.byKey(const ValueKey('open-vehicle-profile')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toggle-driver-mode')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('open-vehicle-profile')), findsNothing);
    });

    testWidgets('big driver leave button returns to lobby', (tester) async {
      await tester.pumpWidget(_app());
      await _enterActiveConvoy(tester);
      await tester.tap(find.byKey(const ValueKey('toggle-driver-mode')));
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('driver-leave-button')));
      await _settle(tester);
      expect(find.text('Neuen Konvoi starten'), findsOneWidget);
    });

    testWidgets('proximity warning becomes a prominent card in driver mode',
        (tester) async {
      final socket = _FakeSocket(convoyId: 'c1');
      await tester.pumpWidget(_app(socket: socket));
      await _enterActiveConvoy(tester);

      // Switch to driver mode FIRST so the card target exists.
      await tester.tap(find.byKey(const ValueKey('toggle-driver-mode')));
      await _settle(tester);

      // Self at origin, peer 50 m to north -> within 500 m default.
      socket.publishLocation(GpsUpdate(
        memberId: 'self',
        latitude: 0,
        longitude: 0,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: DateTime.utc(2026, 5, 13, 12, 0, 0),
      ));
      socket.publishLocation(GpsUpdate(
        memberId: 'buddy',
        latitude: 0.00045,
        longitude: 0,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: DateTime.utc(2026, 5, 13, 12, 0, 1),
      ));
      await _settle(tester);

      expect(find.byKey(const ValueKey('driver-proximity-card')),
          findsOneWidget);
    });
  });

  group('driverModeProvider', () {
    test('defaults to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(driverModeProvider), isFalse);
    });

    test('is mutable via notifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(driverModeProvider.notifier).state = true;
      expect(container.read(driverModeProvider), isTrue);
    });
  });
}
