import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/realtime/connection_status.dart';
import 'package:crew_link/core/realtime/convoy_socket_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ── Fake WebSocket helpers ────────────────────────────────────────────────────

class _CaptureSink implements WebSocketSink {
  final List<dynamic> sent = [];
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic event) => sent.add(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    if (!_done.isCompleted) _done.complete();
    return Future<void>.value();
  }

  @override
  Future<void> get done => _done.future;
}

/// A fully controllable fake [WebSocketChannel].
///
/// [push] injects an inbound frame; [closeStream] simulates a graceful server
/// close (triggers the `onDone` path in [ConvoySocketClient]).
class _FakeWebSocketChannel with StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _inCtrl =
      StreamController<dynamic>(sync: true);
  final _CaptureSink _captureSink = _CaptureSink();

  @override
  Stream<dynamic> get stream => _inCtrl.stream;

  @override
  WebSocketSink get sink => _captureSink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  void push(String data) => _inCtrl.add(data);

  Future<void> closeStream() => _inCtrl.close();

  List<dynamic> get sent => _captureSink.sent;
}

void main() {
  group('ConvoySocketClient reconnect', () {
    test('emits reconnecting and retries after factory failure', () async {
      var attempts = 0;
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        authToken: 't',
        channelFactory: (_) {
          attempts += 1;
          throw Exception('boom');
        },
        baseRetryDelay: const Duration(milliseconds: 20),
        maxRetryDelay: const Duration(milliseconds: 200),
        random: math.Random(42),
      );

      final statuses = <ConnectionStatus>[];
      final sub = client.connectionStatus.listen(statuses.add);

      unawaited(client.connect());
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(attempts, greaterThanOrEqualTo(3));
      expect(
        statuses,
        containsAllInOrder(<ConnectionStatus>[
          ConnectionStatus.connecting,
          ConnectionStatus.reconnecting,
          ConnectionStatus.connecting,
          ConnectionStatus.reconnecting,
        ]),
      );

      await sub.cancel();
      await client.disconnect();
    });

    test('disconnect stops the reconnect loop', () async {
      var attempts = 0;
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        authToken: 't',
        channelFactory: (_) {
          attempts += 1;
          throw Exception('boom');
        },
        baseRetryDelay: const Duration(milliseconds: 20),
        random: math.Random(42),
      );

      unawaited(client.connect());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await client.disconnect();
      final atDisconnect = attempts;

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(attempts, atDisconnect,
          reason: 'no new factory calls expected after disconnect()');
    });

    test('backoff delay grows on consecutive failures', () async {
      final times = <int>[];
      final start = DateTime.now();
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        authToken: 't',
        channelFactory: (_) {
          times.add(DateTime.now().difference(start).inMilliseconds);
          throw Exception('boom');
        },
        baseRetryDelay: const Duration(milliseconds: 30),
        maxRetryDelay: const Duration(seconds: 5),
        random: math.Random(0), // deterministic jitter ≈ -0.25..0.25
      );

      unawaited(client.connect());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await client.disconnect();

      expect(times.length, greaterThanOrEqualTo(3),
          reason: 'expected at least three connect attempts');
      final delta12 = times[1] - times[0];
      final delta23 = times[2] - times[1];
      // Second gap should be ~2× first gap (modulo jitter).
      expect(delta23, greaterThan(delta12));
    });

    test('publishLocation silently no-ops when not connected', () async {
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        authToken: 't',
        channelFactory: (_) => throw Exception('boom'),
        baseRetryDelay: const Duration(milliseconds: 5),
      );
      final update = GpsUpdate(
        memberId: 'me',
        latitude: 52.5,
        longitude: 13.4,
        headingDegrees: 0,
        speedMps: 0,
        timestamp: DateTime.utc(2026, 5, 13),
      );
      // Must NOT throw — caller is fire-and-forget.
      expect(() => client.publishLocation(update), returnsNormally);
      await client.disconnect();
    });

    test('connect emits "connecting" immediately', () async {
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        authToken: 't',
        channelFactory: (_) {
          throw Exception('boom');
        },
        baseRetryDelay: const Duration(milliseconds: 5),
      );
      // Verify the synchronous getter — useful for the StreamProvider
      // seed pattern in convoy_providers.dart.
      expect(client.currentStatus, ConnectionStatus.connecting);
      await client.disconnect();
    });
  });

  group('ConvoySocketClient wire protocol', () {
    test('connects to /convoys/:id/stream with ?token= query param', () async {
      Uri? captured;
      final fake = _FakeWebSocketChannel();
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'convoy-42',
        authToken: 'tok-123',
        channelFactory: (uri) {
          captured = uri;
          return fake;
        },
      );

      unawaited(client.connect());
      await Future<void>.delayed(Duration.zero);

      expect(captured?.path, '/convoys/convoy-42/stream');
      expect(captured?.queryParameters['token'], 'tok-123');
      expect(captured?.scheme, 'ws');
      await client.disconnect();
    });

    test('status sequence is connecting → connected on successful open',
        () async {
      final fake = _FakeWebSocketChannel();
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        authToken: 't',
        channelFactory: (_) => fake,
      );

      final statuses = <ConnectionStatus>[];
      final sub = client.connectionStatus.listen(statuses.add);

      unawaited(client.connect());
      await Future<void>.delayed(Duration.zero);

      expect(
        statuses,
        containsAllInOrder(<ConnectionStatus>[
          ConnectionStatus.connecting,
          ConnectionStatus.connected,
        ]),
      );
      await sub.cancel();
      await client.disconnect();
    });

    test('decodes incoming gps frame into GpsUpdate on gpsUpdates stream',
        () async {
      final fake = _FakeWebSocketChannel();
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        authToken: 't',
        channelFactory: (_) => fake,
      );

      final updates = <GpsUpdate>[];
      final sub = client.gpsUpdates.listen(updates.add);

      unawaited(client.connect());
      await Future<void>.delayed(Duration.zero);

      fake.push(jsonEncode(<String, Object?>{
        'type': 'gps',
        'payload': <String, Object?>{
          'memberId': 'alice',
          'latitude': 52.5200,
          'longitude': 13.4050,
          'heading': 90.0,
          'speed': 10.0,
          'timestamp': '2026-05-14T10:00:00.000Z',
        },
      }));
      await Future<void>.delayed(Duration.zero);

      expect(updates, hasLength(1));
      expect(updates.first.memberId, 'alice');
      expect(updates.first.latitude, 52.5200);
      await sub.cancel();
      await client.disconnect();
    });

    test('graceful server close triggers reconnect', () async {
      var attempts = 0;
      _FakeWebSocketChannel? latest;
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        authToken: 't',
        channelFactory: (_) {
          attempts += 1;
          latest = _FakeWebSocketChannel();
          return latest!;
        },
        baseRetryDelay: const Duration(milliseconds: 20),
        random: math.Random(0),
      );

      unawaited(client.connect());
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);

      unawaited(latest!.closeStream());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(attempts, greaterThan(1),
          reason: 'client must reconnect after graceful server close');
      await client.disconnect();
    });

    test('publishLocation encodes gps frame to the WebSocket sink', () async {
      final fake = _FakeWebSocketChannel();
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        authToken: 't',
        channelFactory: (_) => fake,
      );

      unawaited(client.connect());
      await Future<void>.delayed(Duration.zero);

      client.publishLocation(
        GpsUpdate(
          memberId: 'me',
          latitude: 48.1351,
          longitude: 11.5820,
          headingDegrees: 270,
          speedMps: 15,
          timestamp: DateTime.utc(2026, 5, 14),
        ),
      );

      expect(fake.sent, hasLength(1));
      final decoded =
          jsonDecode(fake.sent.first as String) as Map<String, dynamic>;
      expect(decoded['type'], 'gps');
      final payload = decoded['payload'] as Map<String, dynamic>;
      expect(payload['memberId'], 'me');
      expect(payload['latitude'], 48.1351);
      expect(payload['heading'], 270.0);
      await client.disconnect();
    });
  });
}
