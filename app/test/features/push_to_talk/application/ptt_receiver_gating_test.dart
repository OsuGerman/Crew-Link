import 'dart:convert';

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/push_to_talk/application/livekit_ptt_session.dart';
import 'package:crew_link/features/push_to_talk/application/ptt_providers.dart';
import 'package:crew_link/features/push_to_talk/data/livekit_ptt_repository.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_token_fetcher.dart';
import 'package:crew_link/features/push_to_talk/data/webrtc_ptt_receiver.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Stub statt FirebaseDatabase.instance (wirft ohne Firebase-Init) —
/// gleiches Muster wie der Web-Preview-Stub in main_web_preview.dart.
class _FakeFirebaseDatabase implements FirebaseDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CountingReceiver extends WebRtcPttReceiver {
  _CountingReceiver()
      : super(
          convoyId: 'c1',
          localUserId: 'me',
          database: _FakeFirebaseDatabase(),
        );

  var starts = 0;
  var stops = 0;

  @override
  Future<void> start() async {
    starts += 1;
  }

  @override
  Future<void> stop() async {
    stops += 1;
  }
}

class _FakeRoomHandle implements LiveKitRoomHandle {
  var closed = false;

  @override
  set onDisconnected(void Function()? callback) {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  late List<_CountingReceiver> receivers;

  /// Container mit gemocktem Token-Fetcher ([status] = Antwort der
  /// Token-Route) und Zähl-Receivern statt echtem RTDB-Empfänger.
  ProviderContainer containerWith({required int status}) {
    receivers = [];
    final fetcher = PttTokenFetcher(
      config: ApiConfig.local(),
      tokenProvider: () async => 'auth',
      client: MockClient((req) async {
        final body = status == 200
            ? jsonEncode({
                'url': 'wss://livekit.example',
                'token': 'lk-token',
                'roomName': 'convoy-c1',
              })
            : '{"error":"x"}';
        return http.Response(body, status);
      }),
    );
    final container = ProviderContainer(overrides: [
      selfMemberIdProvider.overrideWithValue('me'),
      pttTokenFetcherProvider.overrideWithValue(fetcher),
      livekitRoomConnectorProvider.overrideWithValue(
        (_, __) async => _FakeRoomHandle(),
      ),
      pttReceiverFactoryProvider.overrideWithValue((convoyId, localUserId) {
        final receiver = _CountingReceiver();
        receivers.add(receiver);
        return receiver;
      }),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('pttReceiverProvider – Gating gegen doppeltes Audio', () {
    test('LiveKit-Session aktiv (200) → P2P-Receiver startet NIE', () async {
      final container = containerWith(status: 200);
      container.listen(livekitPttSessionProvider('c1'), (_, __) {});
      container.listen(pttReceiverProvider('c1'), (_, __) {});

      await container.read(livekitPttSessionProvider('c1').future);
      await Future<void>.delayed(Duration.zero);

      expect(
        receivers.every((r) => r.starts == 0),
        isTrue,
        reason: 'LiveKit spielt Remote-Audio selbst ab — kein Doppel-Receiver',
      );
    });

    test('503 → P2P-Receiver startet wie bisher', () async {
      final container = containerWith(status: 503);
      container.listen(livekitPttSessionProvider('c1'), (_, __) {});
      container.listen(pttReceiverProvider('c1'), (_, __) {});

      await container.read(livekitPttSessionProvider('c1').future);
      await Future<void>.delayed(Duration.zero);

      expect(
        receivers.where((r) => r.starts == 1),
        hasLength(1),
        reason: 'ohne LiveKit-Env bleibt der RTDB-Empfangspfad zuständig',
      );
    });

    test('Konvoi-Austritt (Dispose) stoppt den laufenden Receiver', () async {
      final container = containerWith(status: 503);
      container.listen(livekitPttSessionProvider('c1'), (_, __) {});
      container.listen(pttReceiverProvider('c1'), (_, __) {});
      await container.read(livekitPttSessionProvider('c1').future);
      await Future<void>.delayed(Duration.zero);
      final started = receivers.singleWhere((r) => r.starts == 1);

      container.dispose();

      expect(started.stops, 1);
    });
  });
}
