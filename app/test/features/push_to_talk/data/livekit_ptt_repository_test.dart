import 'dart:async';
import 'dart:typed_data';

import 'package:crew_link/features/push_to_talk/data/livekit_ptt_repository.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_token_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRoomHandle implements LiveKitRoomHandle {
  final micCalls = <bool>[];
  var closed = false;

  @override
  set onDisconnected(void Function()? callback) {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    micCalls.add(enabled);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// Lässt das erste Mikro-Einschalten am [micGate] hängen — simuliert den
/// laufenden nativen Mic-Start, während die Taste schon losgelassen wird.
class _GatedMicRoomHandle extends _FakeRoomHandle {
  final micGate = Completer<void>();

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    micCalls.add(enabled);
    if (enabled) await micGate.future;
  }
}

void main() {
  group('LiveKitPttRepository – Mic-Toggle auf geteilter Session', () {
    test('startTransmitting löst die Session auf und öffnet NUR das Mikro',
        () async {
      final handle = _FakeRoomHandle();
      final resolvedWith = <String>[];
      final repo = LiveKitPttRepository(
        sessionResolver: (convoyId) async {
          resolvedWith.add(convoyId);
          return handle;
        },
      );

      await repo.startTransmitting('c1');

      expect(resolvedWith, ['c1']);
      expect(handle.micCalls, [true]);
      expect(handle.closed, isFalse, reason: 'kein Connect/Close pro Druck');
    });

    test('stopTransmitting mutet nur — Raum bleibt für Hörer offen',
        () async {
      final handle = _FakeRoomHandle();
      final repo = LiveKitPttRepository(sessionResolver: (_) async => handle);

      await repo.startTransmitting('c1');
      await repo.stopTransmitting();

      expect(handle.micCalls, [true, false]);
      expect(handle.closed, isFalse,
          reason: 'die geteilte Session überlebt den Tastendruck');
    });

    test('stopTransmitting ohne Start ist ein No-op', () async {
      final repo = LiveKitPttRepository(
        sessionResolver: (_) async => _FakeRoomHandle(),
      );

      await expectLater(repo.stopTransmitting(), completes);
    });

    test('Doppel-Start öffnet das Mikro nicht zweimal', () async {
      final handle = _FakeRoomHandle();
      var resolves = 0;
      final repo = LiveKitPttRepository(
        sessionResolver: (_) async {
          resolves += 1;
          return handle;
        },
      );

      await repo.startTransmitting('c1');
      await repo.startTransmitting('c1');

      expect(resolves, 1);
      expect(handle.micCalls, [true]);
    });

    test('Release während des Session-Aufbaus lässt kein offenes Mikro',
        () async {
      final handle = _FakeRoomHandle();
      final gate = Completer<void>();
      final repo = LiveKitPttRepository(
        sessionResolver: (_) async {
          await gate.future;
          return handle;
        },
      );

      final start = repo.startTransmitting('c1');
      await repo.stopTransmitting();
      gate.complete();
      await start;

      expect(handle.micCalls, isEmpty,
          reason: 'Mikro darf nach dem Release nicht nachträglich angehen');
      expect(handle.closed, isFalse, reason: 'Session gehört dem Provider');
    });

    test('Release während des Mikro-Starts mutet sofort wieder', () async {
      final handle = _GatedMicRoomHandle();
      final repo = LiveKitPttRepository(sessionResolver: (_) async => handle);

      final start = repo.startTransmitting('c1');
      // Bis zum hängenden setMicrophoneEnabled(true) laufen lassen.
      await Future<void>.delayed(Duration.zero);
      final stop = repo.stopTransmitting();
      handle.micGate.complete();
      await start;
      await stop;

      expect(handle.micCalls.first, isTrue);
      expect(handle.micCalls.last, isFalse,
          reason: 'Endzustand nach Quick-Tap muss gemutet sein');
    });

    test('P2P-Entscheidung (Resolver null) → PttTokenException 503',
        () async {
      final repo = LiveKitPttRepository(sessionResolver: (_) async => null);

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
        sessionResolver: (_) async => _FakeRoomHandle(),
      );

      expect(() => repo.sendFrame(Uint8List(4)), returnsNormally);
    });
  });
}
