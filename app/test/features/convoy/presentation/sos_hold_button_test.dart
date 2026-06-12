import 'dart:async';

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/models/hazard_report.dart';
import 'package:crew_link/core/realtime/connection_status.dart';
import 'package:crew_link/core/realtime/convoy_socket_client.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/presentation/sos_hold_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pattern: Fake-Sockets MÜSSEN currentStatus + connectionStatus überschreiben.
class _FakeSocket extends ConvoySocketClient {
  _FakeSocket({this.status = ConnectionStatus.connected})
      : super(
          convoyId: 'c1',
          config: ApiConfig.local(),
          tokenProvider: _token,
        );

  static Future<String> _token() async => 'tok';

  final ConnectionStatus status;
  final List<HazardReport> publishedHazards = [];

  @override
  ConnectionStatus get currentStatus => status;

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      Stream<ConnectionStatus>.value(status);

  @override
  void publishHazardReport(HazardReport report) =>
      publishedHazards.add(report);

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}
}

GpsUpdate _selfPos() => GpsUpdate(
      memberId: 'self',
      latitude: 52.52,
      longitude: 13.405,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: DateTime.utc(2026, 6, 12),
    );

/// Minimal-Harness: ein Button, der [broadcastSos] auslöst — testet die
/// Feedback-Logik der Funktion ohne den 3-s-Hold-Gestik-Aufwand.
Widget _app(_FakeSocket socket) {
  return ProviderScope(
    overrides: [
      convoySocketProvider.overrideWith((ref) => socket),
      selfMemberIdProvider.overrideWithValue('self'),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            key: const ValueKey('fire-sos'),
            onPressed: () => broadcastSos(
              context,
              ref,
              convoyId: 'c1',
              selfPos: _selfPos(),
              selfId: 'self',
            ),
            child: const Text('fire'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('broadcastSos feedback', () {
    testWidgets('connected: bestätigt den Versand an alle', (tester) async {
      final socket = _FakeSocket();
      await tester.pumpWidget(_app(socket));

      await tester.tap(find.byKey(const ValueKey('fire-sos')));
      await tester.pump();

      expect(socket.publishedHazards.single.type, HazardType.sos);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('SOS an alle gesendet'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'offline: verspricht ehrlich "wird gesendet, sobald online" '
        'statt eines falschen Erfolgs', (tester) async {
      final socket = _FakeSocket(status: ConnectionStatus.reconnecting);
      await tester.pumpWidget(_app(socket));

      await tester.tap(find.byKey(const ValueKey('fire-sos')));
      await tester.pump();

      // Der Hazard wird trotzdem gemeldet — er landet in der Offline-Queue
      // des echten Clients; die UI behauptet nur keinen sofortigen Versand.
      expect(socket.publishedHazards.single.type, HazardType.sos);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching:
              find.textContaining('wird gesendet, sobald online'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('SOS an alle gesendet'),
        ),
        findsNothing,
      );
    });
  });

  group('SosHoldButton', () {
    testWidgets('zeigt GPS-Wartehinweis solange disabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SosHoldButton(onTriggered: null)),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sos-hold-button')),
          matching: find.textContaining('warte auf GPS'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('feuert erst nach 3 s Halten, nicht bei kurzem Tap',
        (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SosHoldButton(onTriggered: () => fired += 1),
          ),
        ),
      );

      // Kurzer Tap → Guard greift, kein SOS.
      await tester.tap(find.byKey(const ValueKey('sos-hold-button')));
      await tester.pumpAndSettle();
      expect(fired, 0);

      // 3 s halten → SOS.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sos-hold-button'))),
      );
      await tester.pump(); // Ticker-Start (elapsed 0)
      await tester.pump(const Duration(seconds: 1));
      // Mitten im Hold: Countdown-Label sichtbar, noch nicht gefeuert.
      expect(find.textContaining('Halten'), findsOneWidget);
      expect(fired, 0);
      // Über die 3-s-Marke hinaus (Simulation braucht elapsed > duration).
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(fired, 1);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
