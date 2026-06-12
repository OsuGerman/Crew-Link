import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/features/push_to_talk/data/livekit_ptt_repository.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_token_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeRoomHandle implements LiveKitRoomHandle {
  final micCalls = <bool>[];
  var closed = false;

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    micCalls.add(enabled);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

PttTokenFetcher _fetcher({int status = 200}) => PttTokenFetcher(
      config: ApiConfig.local(),
      tokenProvider: () async => 'auth',
      client: MockClient((req) async {
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
  group('LiveKitPttRepository', () {
    test('startTransmitting verbindet mit Grant-URL/-Token und öffnet Mikro',
        () async {
      final handle = _FakeRoomHandle();
      final connected = <(String, String)>[];
      final repo = LiveKitPttRepository(
        tokenFetcher: _fetcher(),
        connector: (url, token) async {
          connected.add((url, token));
          return handle;
        },
      );

      await repo.startTransmitting('c1');

      expect(connected.single, ('wss://livekit.example', 'lk-token'));
      expect(handle.micCalls, [true]);
      expect(handle.closed, isFalse);
    });

    test('stopTransmitting schließt Mikro und trennt die Verbindung',
        () async {
      final handle = _FakeRoomHandle();
      final repo = LiveKitPttRepository(
        tokenFetcher: _fetcher(),
        connector: (_, __) async => handle,
      );

      await repo.startTransmitting('c1');
      await repo.stopTransmitting();

      expect(handle.micCalls, [true, false]);
      expect(handle.closed, isTrue);
    });

    test('stopTransmitting ohne Start ist ein No-op', () async {
      final repo = LiveKitPttRepository(
        tokenFetcher: _fetcher(),
        connector: (_, __) async => _FakeRoomHandle(),
      );

      await expectLater(repo.stopTransmitting(), completes);
    });

    test('Doppel-Start verbindet nicht zweimal', () async {
      var connects = 0;
      final repo = LiveKitPttRepository(
        tokenFetcher: _fetcher(),
        connector: (_, __) async {
          connects += 1;
          return _FakeRoomHandle();
        },
      );

      await repo.startTransmitting('c1');
      await repo.startTransmitting('c1');

      expect(connects, 1);
    });

    test('Release während des Verbindungsaufbaus lässt kein offenes Mikro',
        () async {
      final handle = _FakeRoomHandle();
      final gate = Completer<void>();
      final repo = LiveKitPttRepository(
        tokenFetcher: _fetcher(),
        connector: (_, __) async {
          await gate.future;
          return handle;
        },
      );

      final start = repo.startTransmitting('c1');
      await repo.stopTransmitting();
      gate.complete();
      await start;

      expect(handle.closed, isTrue);
      expect(handle.micCalls, isEmpty);
    });

    test('503 der Token-Route propagiert als PttTokenException', () async {
      final repo = LiveKitPttRepository(
        tokenFetcher: _fetcher(status: 503),
        connector: (_, __) async => fail('darf ohne Token nicht verbinden'),
      );

      await expectLater(
        repo.startTransmitting('c1'),
        throwsA(
          isA<PttTokenException>()
              .having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('sendFrame ist ein No-op (LiveKit encodiert selbst)', () {
      final repo = LiveKitPttRepository(
        tokenFetcher: _fetcher(),
        connector: (_, __) async => _FakeRoomHandle(),
      );

      expect(() => repo.sendFrame(Uint8List(4)), returnsNormally);
    });
  });
}
