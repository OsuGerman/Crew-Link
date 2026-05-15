import 'dart:async';
import 'dart:convert';

import 'package:crew_link/app/crew_link_app.dart';
import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/realtime/connection_status.dart';
import 'package:crew_link/core/realtime/convoy_socket_client.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/application/driver_mode.dart';
import 'package:crew_link/features/onboarding/application/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
    ],
    child: const CrewLinkApp(),
  );
}

Future<void> _enterActiveConvoy(WidgetTester tester) async {
  await tester.tap(find.text('Neuen Konvoi erstellen'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Trip');
  await tester.tap(find.text('Erstellen'));
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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-vehicle-profile')), findsNothing);
    });

    testWidgets('big driver leave button returns to lobby', (tester) async {
      await tester.pumpWidget(_app());
      await _enterActiveConvoy(tester);
      await tester.tap(find.byKey(const ValueKey('toggle-driver-mode')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('driver-leave-button')));
      await tester.pumpAndSettle();
      expect(find.text('Neuen Konvoi erstellen'), findsOneWidget);
    });

    testWidgets('proximity warning becomes a prominent card in driver mode',
        (tester) async {
      final socket = _FakeSocket(convoyId: 'c1');
      await tester.pumpWidget(_app(socket: socket));
      await _enterActiveConvoy(tester);

      // Switch to driver mode FIRST so the card target exists.
      await tester.tap(find.byKey(const ValueKey('toggle-driver-mode')));
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
