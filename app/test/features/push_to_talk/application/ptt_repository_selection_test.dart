import 'dart:convert';
import 'dart:typed_data';

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
import 'package:crew_link/features/push_to_talk/application/livekit_ptt_session.dart';
import 'package:crew_link/features/push_to_talk/application/ptt_providers.dart';
import 'package:crew_link/features/push_to_talk/data/livekit_ptt_repository.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_repository.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_token_fetcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeWebRtcRepository implements PttRepository {
  final startedWith = <String>[];
  var stops = 0;

  @override
  Future<void> startTransmitting(String convoyId) async {
    startedWith.add(convoyId);
  }

  @override
  Future<void> stopTransmitting() async {
    stops += 1;
  }

  @override
  void sendFrame(Uint8List frame) {}
}

class _FakeRoomHandle implements LiveKitRoomHandle {
  final micCalls = <bool>[];

  @override
  set onDisconnected(void Function()? callback) {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    micCalls.add(enabled);
  }

  @override
  Future<void> close() async {}
}

class _RecordingReporter implements CrashReporter {
  final errors = <Object>[];

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    Map<String, Object?> tags = const {},
  }) async {
    errors.add(error);
  }

  @override
  Future<void> setUser({required String memberId}) async {}
}

void main() {
  late _FakeWebRtcRepository webrtcFake;
  late _FakeRoomHandle roomHandle;
  late List<(String, String)> connected;
  late int tokenRequests;
  late _RecordingReporter reporter;

  /// Container mit gemocktem Token-Fetcher: [status] simuliert die Antwort
  /// der Backend-Route POST /convoys/:id/ptt-token. Das listen auf den
  /// Session-Provider entspricht dem Watch der ActiveConvoyView
  /// (Konvoi-Eintritt) — dort fällt jetzt die Transport-Entscheidung.
  ProviderContainer containerWith({required int status}) {
    webrtcFake = _FakeWebRtcRepository();
    roomHandle = _FakeRoomHandle();
    connected = [];
    tokenRequests = 0;
    final fetcher = PttTokenFetcher(
      config: ApiConfig.local(),
      tokenProvider: () async => 'firebase-id-token',
      client: MockClient((req) async {
        tokenRequests += 1;
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
    final container = ProviderContainer(
      overrides: [
        pttTokenFetcherProvider.overrideWithValue(fetcher),
        livekitRoomConnectorProvider.overrideWithValue((url, token) async {
          connected.add((url, token));
          return roomHandle;
        }),
        webrtcPttRepositoryProvider.overrideWithValue(webrtcFake),
      ],
    );
    addTearDown(container.dispose);
    container.listen(livekitPttSessionProvider('c1'), (_, __) {});
    return container;
  }

  setUp(() {
    reporter = _RecordingReporter();
    ObservabilityBootstrap.build(overrideForTesting: reporter);
  });

  group('pttRepositoryProvider – Transportauswahl beim Konvoi-Eintritt', () {
    test(
        'Standard ist LiveKit: ein Raum-Join beim Eintritt (gemutet), '
        'Tastendruck togglet nur das Mikro', () async {
      final container = containerWith(status: 200);
      await container.read(livekitPttSessionProvider('c1').future);
      final repo = container.read(pttRepositoryProvider);

      await repo.startTransmitting('c1');
      await repo.stopTransmitting();

      expect(connected.single, ('wss://livekit.example', 'lk-token'),
          reason: 'genau EIN Connect — nicht einer pro Tastendruck');
      expect(roomHandle.micCalls, [false, true, false],
          reason: 'gemutet beigetreten, dann Mic-Toggle pro Druck');
      expect(tokenRequests, 1);
      expect(webrtcFake.startedWith, isEmpty);
    });

    test('Token-Route 503 beim Eintritt → P2P-WebRTC, kein Raum-Connect',
        () async {
      final container = containerWith(status: 503);
      await container.read(livekitPttSessionProvider('c1').future);
      final repo = container.read(pttRepositoryProvider);

      await repo.startTransmitting('c1');
      await repo.stopTransmitting();

      expect(webrtcFake.startedWith, ['c1']);
      expect(webrtcFake.stops, 1);
      expect(connected, isEmpty);
      expect(tokenRequests, 1, reason: 'Entscheidung fällt beim Eintritt');

      await repo.startTransmitting('c1');
      expect(tokenRequests, 1, reason: 'kein Probe-Roundtrip pro Druck');
      expect(webrtcFake.startedWith, ['c1', 'c1']);
    });

    test('Token-Route 401 → kein Fallback, gemeldet, neuer Anlauf pro Druck',
        () async {
      final container = containerWith(status: 401);
      await expectLater(
        container.read(livekitPttSessionProvider('c1').future),
        throwsA(isA<PttTokenException>()),
      );
      expect(tokenRequests, 1, reason: 'ein Join-Versuch beim Eintritt');
      final repo = container.read(pttRepositoryProvider);

      await expectLater(repo.startTransmitting('c1'), completes);
      await Future<void>.delayed(Duration.zero);

      expect(tokenRequests, 2,
          reason: 'genau ein neuer Session-Anlauf pro Tastendruck');
      expect(webrtcFake.startedWith, isEmpty,
          reason: '401 darf keinen Auth-Bug durch P2P maskieren');
      expect(connected, isEmpty);
      final reported = reporter.errors.whereType<PttTokenException>();
      expect(reported, isNotEmpty);
      expect(reported.every((e) => e.statusCode == 401), isTrue);

      // Nächster Tastendruck versucht es erneut (z. B. nach Token-Refresh).
      await repo.startTransmitting('c1');
      expect(tokenRequests, 3);
    });
  });
}
