import 'dart:async';
import 'dart:convert';

import 'package:crew_link/features/convoy/presentation/convoy_home_screen.dart';
import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/realtime/connection_status.dart';
import 'package:crew_link/core/realtime/convoy_socket_client.dart';
import 'package:crew_link/features/auth/application/auth_providers.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/onboarding/application/onboarding_state.dart';
import 'package:crew_link/features/push_to_talk/presentation/ptt_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../support/active_view_test_overrides.dart';

http.Client _client(http.Response Function(http.Request req) handler) {
  return MockClient((req) async => handler(req));
}

Map<String, Object?> _fakeConvoyJson({
  String id = 'c1',
  String name = 'Trip',
  String invite = 'ABC123',
  List<Object?>? members,
}) {
  return {
    'id': id,
    'name': name,
    'inviteCode': invite,
    'members': members ?? <Object?>[],
    'proximityWarningMeters': 500,
    'createdAt': '2026-05-13T12:00:00Z',
  };
}

/// In-memory socket client used in widget tests. Skips real network IO
/// while still satisfying the [ConvoySocketClient] interface so the
/// session/proximity providers exercise their real wiring.
class FakeConvoySocketClient extends ConvoySocketClient {
  FakeConvoySocketClient({required super.convoyId})
      : super(
          config: ApiConfig.local(),
          authToken: 'test-token',
        );

  final StreamController<GpsUpdate> _controller =
      StreamController<GpsUpdate>.broadcast();

  @override
  Stream<GpsUpdate> get gpsUpdates => _controller.stream;

  // The fake is always "connected" — no real WebSocket, no reconnect
  // loop. Overriding both the synchronous getter and the stream keeps
  // the convoy-status banner hidden in widget tests.
  @override
  ConnectionStatus get currentStatus => ConnectionStatus.connected;

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      Stream<ConnectionStatus>.value(ConnectionStatus.connected);

  @override
  Future<void> connect() async {}

  @override
  void publishLocation(GpsUpdate update) => _controller.add(update);

  @override
  Future<void> disconnect() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

Widget _app(
  http.Client client, {
  FakeConvoySocketClient? socket,
}) {
  return ProviderScope(
    overrides: [
      httpClientProvider.overrideWithValue(client),
      authTokenProvider.overrideWithValue('test-token'),
      authIdTokenProvider.overrideWith((ref) => 'test-token'),
      selfMemberIdProvider.overrideWithValue('self'),
      devSignedInOverrideProvider.overrideWith((ref) => true),
      clockProvider.overrideWithValue(
        () => DateTime.utc(2026, 5, 13, 12, 0, 30),
      ),
      onboardingCompletedProvider.overrideWith((ref) => true),
      convoySocketFactoryProvider.overrideWithValue(
        ({required convoyId, required authToken}) =>
            socket ?? FakeConvoySocketClient(convoyId: convoyId),
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

/// Navigates the full 3-step ConvoyCreateSheet and submits.
// ActiveConvoyView runs a continuous radar-sweep animation, so pumpAndSettle
// never completes once the active view is shown. Pump a bounded amount
// instead (enough for sheet/page transitions + the in-memory API + setState).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _doCreate(WidgetTester tester, {String name = 'Trip'}) async {
  await tester.tap(find.text('Neuen Konvoi starten'));
  await _settle(tester);
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('convoy-create-step0-btn')));
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('convoy-create-step1-btn')));
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('convoy-create-step2-btn')));
  await _settle(tester);
}

void main() {
  group('ConvoyHomeScreen', () {
    // The active convoy view is designed for a phone-height viewport; the
    // 800x600 widget-test default is too short once the member list + quick
    // actions + SOS stack up. Use a realistic phone surface.
    setUp(() {
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first;
      view.physicalSize = const Size(800, 1200);
      view.devicePixelRatio = 1.0;
      addTearDown(view.reset);
    });

    testWidgets('lobby shows create + join actions', (tester) async {
      await tester.pumpWidget(
        _app(_client((req) => http.Response('{}', 200))),
      );
      expect(find.text('Neuen Konvoi starten'), findsOneWidget);
      expect(find.text('Konvoi beitreten'), findsOneWidget);
    });

    testWidgets('create flow posts to /convoys and shows active view',
        (tester) async {
      http.Request? captured;
      final client = _client((req) {
        captured = req;
        return http.Response(jsonEncode(_fakeConvoyJson(name: 'Trip A')), 200);
      });

      await tester.pumpWidget(_app(client));
      await _doCreate(tester, name: 'Trip A');

      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/convoys');
      expect(captured!.headers['Authorization'], 'Bearer test-token');
      final body = jsonDecode(captured!.body) as Map<String, Object?>;
      expect(body['name'], 'Trip A');
      expect(body['proximityWarningMeters'], 500);

      expect(find.text('Trip A'), findsOneWidget);
      expect(find.textContaining('ABC123'), findsOneWidget);
    });

    testWidgets('join flow posts invite code to /convoys/join',
        (tester) async {
      http.Request? captured;
      final client = _client((req) {
        captured = req;
        return http.Response(jsonEncode(_fakeConvoyJson(invite: 'XYZ789')), 200);
      });

      await tester.pumpWidget(_app(client));
      await tester.tap(find.text('Konvoi beitreten'));
      await _settle(tester);

      await tester.enterText(
          find.byType(TextField, skipOffstage: false), 'XYZ789');
      await tester.pump(); // enable 'Beitreten' (only valid for a 6-char code)
      await tester.tap(find.text('Beitreten'));
      await _settle(tester);

      expect(captured!.url.path, '/convoys/join');
      final body = jsonDecode(captured!.body) as Map<String, Object?>;
      expect(body['inviteCode'], 'XYZ789');

      expect(find.textContaining('XYZ789'), findsOneWidget);
    });

    testWidgets('API failure shows snackbar and stays on lobby',
        (tester) async {
      final client = _client((req) => http.Response('boom', 500));
      await tester.pumpWidget(_app(client));
      await tester.tap(find.text('Konvoi beitreten'));
      await _settle(tester);
      await tester.enterText(
          find.byType(TextField, skipOffstage: false), 'BADXYZ');
      await tester.pump(); // enable 'Beitreten' (only valid for a 6-char code)
      await tester.tap(find.text('Beitreten'));
      await _settle(tester);

      expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
      expect(find.text('Neuen Konvoi starten'), findsOneWidget);
    });

    testWidgets('leave button calls DELETE /convoys/:id/membership and returns to lobby',
        (tester) async {
      final requests = <http.BaseRequest>[];
      final client = _client((req) {
        requests.add(req);
        if (req.method == 'DELETE') {
          return http.Response('', 204);
        }
        return http.Response(jsonEncode(_fakeConvoyJson()), 200);
      });
      await tester.pumpWidget(_app(client));
      await _doCreate(tester);

      final leaveFinder = find.byKey(const ValueKey('leave-convoy-action'));
      await tester.ensureVisible(leaveFinder);
      await _settle(tester);
      await tester.tap(leaveFinder);
      await _settle(tester);
      // _LeaveButton opens a confirm dialog; tap its 'Verlassen' action.
      await tester.tap(find.text('Verlassen'));
      await _settle(tester);

      final deleteReq = requests.firstWhere((r) => r.method == 'DELETE');
      expect(deleteReq.url.path, '/convoys/c1/membership');
      expect(deleteReq.headers['Authorization'], 'Bearer test-token');
      expect(find.text('Neuen Konvoi starten'), findsOneWidget);
    });

    testWidgets('leave API failure shows snackbar and stays in active view',
        (tester) async {
      final client = _client((req) {
        if (req.method == 'DELETE') {
          return http.Response('server error', 500);
        }
        return http.Response(jsonEncode(_fakeConvoyJson()), 200);
      });
      await tester.pumpWidget(_app(client));
      await _doCreate(tester);

      final leaveFinder = find.byKey(const ValueKey('leave-convoy-action'));
      await tester.ensureVisible(leaveFinder);
      await _settle(tester);
      await tester.tap(leaveFinder);
      await _settle(tester);
      // _LeaveButton opens a confirm dialog; tap its 'Verlassen' action.
      await tester.tap(find.text('Verlassen'));
      await _settle(tester);

      expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
      expect(find.text('Neuen Konvoi starten'), findsNothing);
    });

    testWidgets('members sheet lists one row per active member',
        (tester) async {
      final socket = FakeConvoySocketClient(convoyId: 'c1');
      final client = _client(
        (req) => http.Response(jsonEncode(_fakeConvoyJson()), 200),
      );
      await tester.pumpWidget(_app(client, socket: socket));
      await _doCreate(tester);

      socket.publishLocation(GpsUpdate(
        memberId: 'self',
        latitude: 52.5200,
        longitude: 13.4060,
        headingDegrees: 0,
        speedMps: 12,
        timestamp: DateTime.utc(2026, 5, 13, 12, 0, 5),
      ));
      socket.publishLocation(GpsUpdate(
        memberId: 'buddy',
        latitude: 53.0000,
        longitude: 13.5000,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: DateTime.utc(2026, 5, 13, 12, 0, 6),
      ));
      await _settle(tester);

      // The map is now full-size; the member list lives one tap away in a sheet.
      final pill = find.byKey(const ValueKey('open-members-sheet'));
      await tester.ensureVisible(pill);
      await _settle(tester);
      await tester.tap(pill);
      await _settle(tester);

      expect(find.byKey(const ValueKey('live-members-tile')), findsOneWidget);
      expect(find.byKey(const ValueKey('member-row-self')), findsOneWidget);
      expect(find.byKey(const ValueKey('member-row-buddy')), findsOneWidget);
      expect(find.text('Du'), findsWidgets);
      // buddy is ~5km north; distance pill shows km (e.g. '5.x km').
      expect(find.textContaining('km'), findsWidgets);
    });

    testWidgets('members pill shows live/total counts and opens the sheet',
        (tester) async {
      final socket = FakeConvoySocketClient(convoyId: 'c1');
      final client = _client(
        (req) => http.Response(jsonEncode(_fakeConvoyJson()), 200),
      );
      await tester.pumpWidget(_app(client, socket: socket));
      await _doCreate(tester);

      socket.publishLocation(GpsUpdate(
        memberId: 'self',
        latitude: 52.5200,
        longitude: 13.4060,
        headingDegrees: 0,
        speedMps: 12,
        timestamp: DateTime.utc(2026, 5, 13, 12, 0, 5),
      ));
      await _settle(tester);

      final pill = find.byKey(const ValueKey('open-members-sheet'));
      expect(pill, findsOneWidget);
      expect(
        find.descendant(
          of: pill,
          matching: find.textContaining('live'),
        ),
        findsOneWidget,
      );
      // The full member list is NOT inline (map stays full-size) until tapped.
      expect(find.byKey(const ValueKey('live-members-tile')), findsNothing);
    });

    testWidgets('map button appears in AppBar when convoy is active',
        (tester) async {
      final client = _client(
        (req) => http.Response(jsonEncode(_fakeConvoyJson()), 200),
      );
      await tester.pumpWidget(_app(client));
      await _doCreate(tester);

      await tester.tap(find.byKey(const ValueKey('overflow-menu')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('open-map')), findsOneWidget);
    });

    testWidgets('map button is absent on lobby', (tester) async {
      await tester.pumpWidget(
        _app(_client((req) => http.Response('{}', 200))),
      );
      await tester.tap(find.byKey(const ValueKey('overflow-menu')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('open-map')), findsNothing);
    });

    testWidgets('PTT button appears in active convoy view', (tester) async {
      final client = _client(
        (req) => http.Response(jsonEncode(_fakeConvoyJson()), 200),
      );
      await tester.pumpWidget(_app(client));
      await _doCreate(tester);

      expect(find.byType(PttButton), findsOneWidget);
    });

    testWidgets('proximity warning banner appears when other member is close',
        (tester) async {
      final socket = FakeConvoySocketClient(convoyId: 'c1');
      final client = _client(
        (req) => http.Response(jsonEncode(_fakeConvoyJson()), 200),
      );
      await tester.pumpWidget(_app(client, socket: socket));
      await _doCreate(tester);

      // self at origin, then other arrives 50m away (well below 500m).
      socket.publishLocation(GpsUpdate(
        memberId: 'self',
        latitude: 0,
        longitude: 0,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: DateTime.utc(2026, 5, 13, 12),
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

      expect(find.byKey(const ValueKey('proximity-banner')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('proximity-banner')),
          matching: find.textContaining('50 m entfernt'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'leader route CTA shows for a leader with no tour and opens RouteSheet',
        (tester) async {
      final client = _client(
        (req) => http.Response(
          jsonEncode(_fakeConvoyJson(members: [
            {'id': 'self', 'displayName': 'Me', 'isLeader': true},
            {'id': 'buddy', 'displayName': 'Buddy'},
          ])),
          200,
        ),
      );
      await tester.pumpWidget(_app(client));
      await _doCreate(tester);

      final cta = find.byKey(const ValueKey('leader-route-cta'));
      expect(cta, findsOneWidget);

      await tester.tap(cta);
      await _settle(tester);
      // RouteSheet renders its ROUTE header.
      expect(find.text('ROUTE'), findsOneWidget);
    });

    testWidgets('leader route CTA is absent for a non-leader member',
        (tester) async {
      final client = _client(
        (req) => http.Response(
          jsonEncode(_fakeConvoyJson(members: [
            {'id': 'someone-else', 'displayName': 'Lead', 'isLeader': true},
            {'id': 'self', 'displayName': 'Me', 'isLeader': false},
          ])),
          200,
        ),
      );
      await tester.pumpWidget(_app(client));
      await _doCreate(tester);

      expect(find.byKey(const ValueKey('leader-route-cta')), findsNothing);
    });
  });
}
