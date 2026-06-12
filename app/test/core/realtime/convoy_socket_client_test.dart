import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/models/hazard_report.dart';
import 'package:crew_link/core/realtime/connection_status.dart';
import 'package:crew_link/core/realtime/convoy_socket_client.dart';
import 'package:fake_async/fake_async.dart';
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

Future<String> _staticToken() async => 't';

GpsUpdate _gps({String memberId = 'me'}) => GpsUpdate(
      memberId: memberId,
      latitude: 52.5,
      longitude: 13.4,
      headingDegrees: 0,
      speedMps: 0,
      timestamp: DateTime.utc(2026, 5, 13),
    );

HazardReport _hazard({String id = 'h1'}) => HazardReport(
      id: id,
      type: HazardType.sos,
      latitude: 52.5,
      longitude: 13.4,
      reporterId: 'me',
      convoyId: 'c',
      createdAt: DateTime.utc(2026, 5, 13),
      expiresAt: DateTime.utc(2026, 5, 13, 0, 30),
    );

void main() {
  group('ConvoySocketClient reconnect', () {
    test('emits reconnecting and retries after factory failure', () async {
      var attempts = 0;
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        tokenProvider: _staticToken,
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
        tokenProvider: _staticToken,
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
        tokenProvider: _staticToken,
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
        tokenProvider: _staticToken,
        channelFactory: (_) => throw Exception('boom'),
        baseRetryDelay: const Duration(milliseconds: 5),
      );
      // Must NOT throw — caller is fire-and-forget.
      expect(() => client.publishLocation(_gps()), returnsNormally);
      await client.disconnect();
    });

    test('connect emits "connecting" immediately', () async {
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        tokenProvider: _staticToken,
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

    test('tokenProvider failure schedules a retry instead of crashing',
        () async {
      var tokenCalls = 0;
      var channelCalls = 0;
      final fake = _FakeWebSocketChannel();
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        tokenProvider: () async {
          tokenCalls += 1;
          if (tokenCalls == 1) throw Exception('firebase offline');
          return 'tok';
        },
        channelFactory: (_) {
          channelCalls += 1;
          return fake;
        },
        baseRetryDelay: const Duration(milliseconds: 10),
        random: math.Random(0),
      );

      unawaited(client.connect());
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(tokenCalls, greaterThanOrEqualTo(2));
      expect(channelCalls, 1,
          reason: 'first attempt must fail BEFORE opening a channel');
      expect(client.currentStatus, ConnectionStatus.connected);
      await client.disconnect();
    });
  });

  group('ConvoySocketClient fresh token per connect', () {
    test('awaits a fresh token for EVERY connect attempt', () async {
      final capturedTokens = <String?>[];
      var tokenCalls = 0;
      _FakeWebSocketChannel? latest;
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        tokenProvider: () async {
          tokenCalls += 1;
          return 'tok-$tokenCalls';
        },
        channelFactory: (uri) {
          capturedTokens.add(uri.queryParameters['token']);
          latest = _FakeWebSocketChannel();
          return latest!;
        },
        baseRetryDelay: const Duration(milliseconds: 10),
        random: math.Random(0),
      );

      unawaited(client.connect());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(capturedTokens, ['tok-1']);

      // Server drop → reconnect must NOT reuse the frozen first token.
      unawaited(latest!.closeStream());
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(capturedTokens.length, greaterThanOrEqualTo(2));
      expect(capturedTokens[1], 'tok-2',
          reason: 'reconnect must carry a freshly awaited token '
              '(expired Firebase tokens otherwise 401-loop forever)');
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
        tokenProvider: () async => 'tok-123',
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
        tokenProvider: _staticToken,
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
        tokenProvider: _staticToken,
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
        tokenProvider: _staticToken,
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
        tokenProvider: _staticToken,
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

  group('ConvoySocketClient offline queue for critical frames', () {
    test('critical frames published while offline are sent after reconnect '
        'in original order', () async {
      var attempts = 0;
      final channels = <_FakeWebSocketChannel>[];
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        tokenProvider: _staticToken,
        channelFactory: (_) {
          attempts += 1;
          final channel = _FakeWebSocketChannel();
          channels.add(channel);
          return channel;
        },
        baseRetryDelay: const Duration(milliseconds: 20),
        random: math.Random(0),
      );

      unawaited(client.connect());
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);

      // Verbindung kippt — SOS + Removal werden WÄHREND der Lücke gemeldet.
      unawaited(channels.first.closeStream());
      await Future<void>.delayed(Duration.zero);
      client.publishHazardReport(_hazard(id: 'sos-1'));
      client.publishHazardRemoval('old-hazard');

      // Reconnect (Backoff 20 ms) → Queue muss in Originalreihenfolge raus.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(attempts, greaterThanOrEqualTo(2));
      final flushed = channels[1].sent.cast<String>();
      expect(flushed, hasLength(2),
          reason: 'SOS during offline gap must NOT be silently dropped');
      final first = jsonDecode(flushed[0]) as Map<String, dynamic>;
      final second = jsonDecode(flushed[1]) as Map<String, dynamic>;
      expect(first['type'], 'hazard');
      expect((first['payload'] as Map)['id'], 'sos-1');
      expect(second['type'], 'hazard_remove');
      await client.disconnect();
    });

    test('gps and quick-action frames are NOT buffered while offline',
        () async {
      var attempts = 0;
      final channels = <_FakeWebSocketChannel>[];
      final client = ConvoySocketClient(
        config: ApiConfig.local(),
        convoyId: 'c',
        tokenProvider: _staticToken,
        channelFactory: (_) {
          attempts += 1;
          final channel = _FakeWebSocketChannel();
          channels.add(channel);
          return channel;
        },
        baseRetryDelay: const Duration(milliseconds: 20),
        random: math.Random(0),
      );

      unawaited(client.connect());
      await Future<void>.delayed(Duration.zero);
      unawaited(channels.first.closeStream());
      await Future<void>.delayed(Duration.zero);

      // Veraltete Positionen nachzusenden wäre falsch → fire-and-forget.
      client.publishLocation(_gps());

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(attempts, greaterThanOrEqualTo(2));
      expect(channels[1].sent, isEmpty,
          reason: 'stale gps must not be replayed after reconnect');
      await client.disconnect();
    });
  });

  group('ConvoySocketClient inbound watchdog', () {
    test('forces reconnect after kInboundSilenceTimeout of silence once '
        'frames were seen', () {
      fakeAsync((async) {
        var attempts = 0;
        _FakeWebSocketChannel? latest;
        final client = ConvoySocketClient(
          config: ApiConfig.local(),
          convoyId: 'c',
          tokenProvider: _staticToken,
          channelFactory: (_) {
            attempts += 1;
            latest = _FakeWebSocketChannel();
            return latest!;
          },
          baseRetryDelay: const Duration(milliseconds: 20),
          random: math.Random(0),
        );

        unawaited(client.connect());
        async.flushMicrotasks();
        expect(attempts, 1);
        expect(client.currentStatus, ConnectionStatus.connected);

        // Erster Inbound-Frame schaltet den Watchdog scharf.
        latest!.push(jsonEncode(<String, Object?>{
          'type': 'gps',
          'payload': <String, Object?>{
            'memberId': 'alice',
            'latitude': 52.52,
            'longitude': 13.40,
            'heading': 0.0,
            'speed': 0.0,
            'timestamp': '2026-05-14T10:00:00.000Z',
          },
        }));
        async.flushMicrotasks();

        // Halbtote Leitung: nichts kommt mehr → nach 35 s muss der normale
        // Reconnect greifen.
        async.elapse(
          ConvoySocketClient.kInboundSilenceTimeout +
              const Duration(seconds: 1),
        );
        async.flushMicrotasks();
        expect(attempts, greaterThanOrEqualTo(2),
            reason: 'silent half-dead link must force a reconnect');

        unawaited(client.disconnect());
        async.flushMicrotasks();
      });
    });

    test('stays connected when the convoy is quiet and no frame was ever '
        'received (solo convoy — no reconnect cycling)', () {
      fakeAsync((async) {
        var attempts = 0;
        final client = ConvoySocketClient(
          config: ApiConfig.local(),
          convoyId: 'c',
          tokenProvider: _staticToken,
          channelFactory: (_) {
            attempts += 1;
            return _FakeWebSocketChannel();
          },
          baseRetryDelay: const Duration(milliseconds: 20),
          random: math.Random(0),
        );

        unawaited(client.connect());
        async.flushMicrotasks();
        expect(attempts, 1);

        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(attempts, 1,
            reason: 'quiet solo convoy must not cycle through reconnects');
        expect(client.currentStatus, ConnectionStatus.connected);

        unawaited(client.disconnect());
        async.flushMicrotasks();
      });
    });

    test('regular inbound frames keep resetting the watchdog', () {
      fakeAsync((async) {
        var attempts = 0;
        _FakeWebSocketChannel? latest;
        final client = ConvoySocketClient(
          config: ApiConfig.local(),
          convoyId: 'c',
          tokenProvider: _staticToken,
          channelFactory: (_) {
            attempts += 1;
            latest = _FakeWebSocketChannel();
            return latest!;
          },
          baseRetryDelay: const Duration(milliseconds: 20),
          random: math.Random(0),
        );

        unawaited(client.connect());
        async.flushMicrotasks();

        // 6 × 20 s Frames = 2 min Gesamtlaufzeit, nie > 35 s Stille.
        for (var i = 0; i < 6; i++) {
          latest!.push(jsonEncode(<String, Object?>{
            'type': 'gps',
            'payload': <String, Object?>{
              'memberId': 'alice',
              'latitude': 52.52,
              'longitude': 13.40,
              'heading': 0.0,
              'speed': 0.0,
              'timestamp': '2026-05-14T10:00:00.000Z',
            },
          }));
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 20));
        }

        expect(attempts, 1,
            reason: 'healthy traffic must never trip the watchdog');
        expect(client.currentStatus, ConnectionStatus.connected);

        unawaited(client.disconnect());
        async.flushMicrotasks();
      });
    });
  });
}
