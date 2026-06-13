import 'dart:convert';

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
import 'package:crew_link/features/push_to_talk/application/livekit_ptt_session.dart';
import 'package:crew_link/features/push_to_talk/data/livekit_ptt_repository.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_token_fetcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeRoomHandle implements LiveKitRoomHandle {
  final micCalls = <bool>[];
  var closed = false;
  void Function()? disconnectCallback;

  @override
  set onDisconnected(void Function()? callback) =>
      disconnectCallback = callback;

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    micCalls.add(enabled);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
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

PttTokenFetcher _fetcher({
  int status = 200,
  void Function()? onRequest,
}) =>
    PttTokenFetcher(
      config: ApiConfig.local(),
      tokenProvider: () async => 'auth',
      client: MockClient((req) async {
        onRequest?.call();
        final body = status == 200
            ? jsonEncode({
                'url': 'wss://livekit.example',
                'token': 'lk-token',
                'roomName': 'convoy-c1',
              })
            : '{"error":"nope"}';
        return http.Response(body, status);
      }),
    );

void main() {
  late _RecordingReporter reporter;

  setUp(() {
    reporter = _RecordingReporter();
    ObservabilityBootstrap.build(overrideForTesting: reporter);
  });

  group('joinLiveKitPttSession', () {
    test('200 → verbindet und tritt GEMUTET bei', () async {
      final handle = _FakeRoomHandle();
      final connected = <(String, String)>[];

      final decision = await joinLiveKitPttSession(
        convoyId: 'c1',
        tokenFetcher: _fetcher(),
        connector: (url, token) async {
          connected.add((url, token));
          return handle;
        },
      );

      expect(connected.single, ('wss://livekit.example', 'lk-token'));
      expect(handle.micCalls, [false], reason: 'Join muss gemutet sein');
      expect(decision.usesP2pFallback, isFalse);
      expect(decision.room, same(handle));
    });

    test('503 → P2P-Entscheidung, kein Raum-Connect, kein Retry', () async {
      var requests = 0;

      final decision = await joinLiveKitPttSession(
        convoyId: 'c1',
        tokenFetcher: _fetcher(status: 503, onRequest: () => requests += 1),
        connector: (_, __) async => fail('503 darf keinen Raum betreten'),
      );

      expect(decision.usesP2pFallback, isTrue);
      expect(requests, 1);
      expect(reporter.errors, isEmpty, reason: '503 ist kein harter Fehler');
    });

    test('401 → kein Retry (Auth nicht maskieren), gemeldet + rethrown',
        () async {
      var requests = 0;

      await expectLater(
        joinLiveKitPttSession(
          convoyId: 'c1',
          tokenFetcher: _fetcher(status: 401, onRequest: () => requests += 1),
          connector: (_, __) async => fail('401 darf keinen Raum betreten'),
        ),
        throwsA(isA<PttTokenException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );

      expect(requests, 1, reason: '4xx ist nicht transient — kein Retry');
      expect(
        reporter.errors.whereType<PttTokenException>().single.statusCode,
        401,
      );
    });

    test('transienter Connect-Fehler → Backoff-Retry bis Erfolg', () async {
      final handle = _FakeRoomHandle();
      final delays = <Duration>[];
      var connects = 0;

      final decision = await joinLiveKitPttSession(
        convoyId: 'c1',
        tokenFetcher: _fetcher(),
        connector: (_, __) async {
          connects += 1;
          if (connects == 1) throw StateError('SFU nicht erreichbar');
          return handle;
        },
        delay: (duration) async => delays.add(duration),
      );

      expect(connects, 2);
      expect(delays, [const Duration(seconds: 2)]);
      expect(decision.room, same(handle));
      expect(reporter.errors, isEmpty,
          reason: 'erfolgreicher Retry wird nicht gemeldet');
    });

    test('transienter Fehler → nach 3 Versuchen gemeldet + rethrown',
        () async {
      final delays = <Duration>[];
      var connects = 0;

      await expectLater(
        joinLiveKitPttSession(
          convoyId: 'c1',
          tokenFetcher: _fetcher(),
          connector: (_, __) async {
            connects += 1;
            throw StateError('SFU nicht erreichbar');
          },
          delay: (duration) async => delays.add(duration),
        ),
        throwsA(isA<StateError>()),
      );

      expect(connects, 3);
      expect(
        delays,
        [const Duration(seconds: 2), const Duration(seconds: 4)],
        reason: 'linear ansteigender Backoff zwischen den Versuchen',
      );
      expect(reporter.errors.whereType<StateError>(), hasLength(1));
    });

    test('Fehler nach Connect schließt den Raum (kein Identity-Leak)',
        () async {
      final handle = _FakeRoomHandle();
      final failing = _FailingMicRoomHandle(handle);

      await expectLater(
        joinLiveKitPttSession(
          convoyId: 'c1',
          tokenFetcher: _fetcher(),
          connector: (_, __) async => failing,
          delay: (_) async {},
        ),
        throwsA(isA<StateError>()),
      );

      expect(handle.closed, isTrue);
    });
  });

  group('livekitPttSessionProvider', () {
    test('Join beim Eintritt (watch): einmal verbunden, gemutet', () async {
      final handle = _FakeRoomHandle();
      var connects = 0;
      final container = ProviderContainer(overrides: [
        pttTokenFetcherProvider.overrideWithValue(_fetcher()),
        livekitRoomConnectorProvider.overrideWithValue((_, __) async {
          connects += 1;
          return handle;
        }),
      ]);
      addTearDown(container.dispose);
      container.listen(livekitPttSessionProvider('c1'), (_, __) {});

      final decision =
          await container.read(livekitPttSessionProvider('c1').future);

      expect(connects, 1);
      expect(handle.micCalls, [false]);
      expect(decision.room, same(handle));
      expect(handle.closed, isFalse);
    });

    test('Konvoi-Austritt (Dispose) schließt den Raum', () async {
      final handle = _FakeRoomHandle();
      final container = ProviderContainer(overrides: [
        pttTokenFetcherProvider.overrideWithValue(_fetcher()),
        livekitRoomConnectorProvider.overrideWithValue((_, __) async => handle),
      ]);
      container.listen(livekitPttSessionProvider('c1'), (_, __) {});
      await container.read(livekitPttSessionProvider('c1').future);

      container.dispose();

      expect(handle.closed, isTrue);
    });

    test('Austritt WÄHREND des Joins lässt keinen offenen Raum zurück',
        () async {
      final handle = _FakeRoomHandle();
      var release = false;
      final container = ProviderContainer(overrides: [
        pttTokenFetcherProvider.overrideWithValue(_fetcher()),
        livekitRoomConnectorProvider.overrideWithValue((_, __) async {
          while (!release) {
            await Future<void>.delayed(Duration.zero);
          }
          return handle;
        }),
      ]);
      container.listen(livekitPttSessionProvider('c1'), (_, __) {});
      await Future<void>.delayed(Duration.zero);

      container.dispose();
      release = true;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(handle.closed, isTrue);
    });

    test('503 → P2P-Entscheidung ohne Join', () async {
      final container = ProviderContainer(overrides: [
        pttTokenFetcherProvider.overrideWithValue(_fetcher(status: 503)),
        livekitRoomConnectorProvider.overrideWithValue(
          (_, __) async => fail('503 darf keinen Raum betreten'),
        ),
      ]);
      addTearDown(container.dispose);
      container.listen(livekitPttSessionProvider('c1'), (_, __) {});

      final decision =
          await container.read(livekitPttSessionProvider('c1').future);

      expect(decision.usesP2pFallback, isTrue);
    });

    test('endgültiger Verbindungsverlust → Session wird neu aufgebaut',
        () async {
      final handles = <_FakeRoomHandle>[];
      final container = ProviderContainer(overrides: [
        pttTokenFetcherProvider.overrideWithValue(_fetcher()),
        livekitRoomConnectorProvider.overrideWithValue((_, __) async {
          final handle = _FakeRoomHandle();
          handles.add(handle);
          return handle;
        }),
      ]);
      addTearDown(container.dispose);
      container.listen(livekitPttSessionProvider('c1'), (_, __) {});
      await container.read(livekitPttSessionProvider('c1').future);

      // livekit_client hat seine internen Reconnects erschöpft.
      handles.single.disconnectCallback!();
      final rejoined =
          await container.read(livekitPttSessionProvider('c1').future);

      expect(handles, hasLength(2), reason: 'Rejoin nach Disconnect');
      expect(handles.first.closed, isTrue, reason: 'alte Session abgebaut');
      expect(rejoined.room, same(handles.last));
    });
  });
}

/// Handle, dessen Mute-Aufruf scheitert — simuliert einen Fehler NACH dem
/// Connect; der Join muss den Raum dann wieder schließen.
class _FailingMicRoomHandle implements LiveKitRoomHandle {
  _FailingMicRoomHandle(this._inner);

  final _FakeRoomHandle _inner;

  @override
  set onDisconnected(void Function()? callback) {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    throw StateError('Mikrofon nicht verfügbar');
  }

  @override
  Future<void> close() => _inner.close();
}
