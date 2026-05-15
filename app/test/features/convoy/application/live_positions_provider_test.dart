import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/core/realtime/connection_status.dart';
import 'package:crew_link/core/realtime/convoy_socket_client.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ── Fake WebSocket ─────────────────────────────────────────────────────────────

class _NullSink implements WebSocketSink {
  @override
  void add(dynamic event) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.drain();
  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      Future<void>.value();
  @override
  Future<void> get done => Future<void>.value();
}

class _FakeChannel with StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _in =
      StreamController<dynamic>(sync: true);

  @override
  Stream<dynamic> get stream => _in.stream;
  @override
  WebSocketSink get sink => _NullSink();
  @override
  Future<void> get ready => Future<void>.value();
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;

  void pushGps(String memberId) => _in.add(jsonEncode({
        'type': 'gps',
        'payload': {
          'memberId': memberId,
          'latitude': 52.52,
          'longitude': 13.40,
          'heading': 0.0,
          'speed': 0.0,
          'timestamp': '2026-05-14T00:00:00.000Z',
        },
      }));

  Future<void> drop() => _in.close();
}

// ── Fixture ────────────────────────────────────────────────────────────────────

Convoy _convoy() => Convoy(
      id: 'c1',
      name: 'Test',
      inviteCode: 'ABC',
      members: const [],
      proximityWarningMeters: 500,
      createdAt: DateTime.utc(2026, 5, 14),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('livePositionsProvider WS binding with reconnect-backoff', () {
    late _FakeChannel latestChannel;
    late ProviderContainer container;

    setUp(() {
      latestChannel = _FakeChannel();
      container = ProviderContainer(
        overrides: [
          currentConvoyProvider.overrideWith((ref) => _convoy()),
          selfMemberIdProvider.overrideWithValue('self'),
          authTokenProvider.overrideWithValue('tok'),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 5, 14)),
          convoySocketFactoryProvider.overrideWithValue(
            ({required convoyId, required authToken}) => ConvoySocketClient(
              config: ApiConfig.local(),
              convoyId: convoyId,
              authToken: authToken,
              channelFactory: (_) {
                latestChannel = _FakeChannel();
                return latestChannel;
              },
              baseRetryDelay: const Duration(milliseconds: 20),
              maxRetryDelay: const Duration(milliseconds: 100),
              random: math.Random(0),
            ),
          ),
        ],
      );
    });

    tearDown(container.dispose);

    test('starts as AsyncLoading before first GPS frame', () {
      final sub = container.listen<AsyncValue<Map<String, GpsUpdate>>>(
          livePositionsProvider, (_, __) {});
      expect(
        container.read(livePositionsProvider),
        isA<AsyncLoading<Map<String, GpsUpdate>>>(),
      );
      sub.close();
    });

    test('emits positions map after first GPS frame arrives', () async {
      final sub = container.listen<AsyncValue<Map<String, GpsUpdate>>>(
          livePositionsProvider, (_, __) {});

      await Future<void>.delayed(Duration.zero);
      latestChannel.pushGps('alice');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final positions = container.read(livePositionsProvider).valueOrNull;
      expect(positions, isNotNull);
      expect(positions!.containsKey('alice'), isTrue);
      sub.close();
    });

    test('accumulates positions from multiple members', () async {
      final sub = container.listen<AsyncValue<Map<String, GpsUpdate>>>(
          livePositionsProvider, (_, __) {});

      await Future<void>.delayed(Duration.zero);
      latestChannel.pushGps('alice');
      latestChannel.pushGps('bob');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final positions = container.read(livePositionsProvider).valueOrNull!;
      expect(positions.keys, containsAll(['alice', 'bob']));
      sub.close();
    });

    test('retains pre-drop positions and receives post-reconnect positions',
        () async {
      final sub = container.listen<AsyncValue<Map<String, GpsUpdate>>>(
          livePositionsProvider, (_, __) {});

      await Future<void>.delayed(Duration.zero);
      latestChannel.pushGps('alice');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Simulate graceful server close — socket will reconnect after ~20 ms backoff
      await latestChannel.drop();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // latestChannel now points to the new channel created by the reconnect
      latestChannel.pushGps('bob');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final positions = container.read(livePositionsProvider).valueOrNull!;
      expect(positions.containsKey('alice'), isTrue,
          reason: 'pre-drop position must be retained in session cache');
      expect(positions.containsKey('bob'), isTrue,
          reason: 'post-reconnect position must flow through');
      sub.close();
    });

    test('convoySocketStatusProvider shows reconnecting after channel drop',
        () async {
      final statuses = <ConnectionStatus>[];
      final posSub = container.listen<AsyncValue<Map<String, GpsUpdate>>>(
          livePositionsProvider, (_, __) {});
      final statusSub = container.listen<AsyncValue<ConnectionStatus>>(
        convoySocketStatusProvider,
        (_, next) {
          final v = next.valueOrNull;
          if (v != null) statuses.add(v);
        },
      );

      await Future<void>.delayed(Duration.zero);
      await latestChannel.drop();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(statuses, contains(ConnectionStatus.reconnecting));
      statusSub.close();
      posSub.close();
    });

    test(
        'connectionStatus sequence includes reconnecting → connecting → connected',
        () async {
      final statuses = <ConnectionStatus>[];
      final posSub = container.listen<AsyncValue<Map<String, GpsUpdate>>>(
          livePositionsProvider, (_, __) {});
      final statusSub = container.listen<AsyncValue<ConnectionStatus>>(
        convoySocketStatusProvider,
        (_, next) {
          final v = next.valueOrNull;
          if (v != null) statuses.add(v);
        },
      );

      await Future<void>.delayed(Duration.zero);
      await latestChannel.drop();
      // 80 ms covers the 20 ms backoff + reconnect handshake with jitter
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        statuses,
        containsAllInOrder(<ConnectionStatus>[
          ConnectionStatus.reconnecting,
          ConnectionStatus.connecting,
          ConnectionStatus.connected,
        ]),
      );
      statusSub.close();
      posSub.close();
    });
  });
}
