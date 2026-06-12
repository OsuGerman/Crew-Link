import 'dart:typed_data';

import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
import 'package:crew_link/features/push_to_talk/data/fallback_ptt_repository.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_repository.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_token_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingPttRepository implements PttRepository {
  _RecordingPttRepository({this.startError});

  final Object? startError;
  final startedWith = <String>[];
  final frames = <Uint8List>[];
  var stops = 0;

  @override
  Future<void> startTransmitting(String convoyId) async {
    startedWith.add(convoyId);
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> stopTransmitting() async {
    stops += 1;
  }

  @override
  void sendFrame(Uint8List frame) => frames.add(frame);
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
  late _RecordingReporter reporter;
  late _RecordingPttRepository fallback;
  var fallbackBuilds = 0;

  FallbackPttRepository repoWith(_RecordingPttRepository primary) {
    fallback = _RecordingPttRepository();
    fallbackBuilds = 0;
    return FallbackPttRepository(
      primary: primary,
      fallbackBuilder: () {
        fallbackBuilds += 1;
        return fallback;
      },
    );
  }

  setUp(() {
    reporter = _RecordingReporter();
    ObservabilityBootstrap.build(overrideForTesting: reporter);
  });

  group('FallbackPttRepository – LiveKit-Pfad', () {
    test('delegiert Start/Frames/Stop an primary, baut keinen Fallback',
        () async {
      final primary = _RecordingPttRepository();
      final repo = repoWith(primary);

      await repo.startTransmitting('c1');
      repo.sendFrame(Uint8List(2));
      await repo.stopTransmitting();

      expect(primary.startedWith, ['c1']);
      expect(primary.frames, hasLength(1));
      expect(primary.stops, 1);
      expect(fallbackBuilds, 0);
    });
  });

  group('FallbackPttRepository – 503-Fallback', () {
    test('503 schaltet dauerhaft auf P2P um (primary nicht erneut versucht)',
        () async {
      final primary =
          _RecordingPttRepository(startError: PttTokenException(503, 'x'));
      final repo = repoWith(primary);

      await repo.startTransmitting('c1');
      repo.sendFrame(Uint8List(2));
      await repo.stopTransmitting();
      await repo.startTransmitting('c1');

      expect(primary.startedWith, ['c1'], reason: 'nur der erste Versuch');
      expect(fallbackBuilds, 1);
      expect(fallback.startedWith, ['c1', 'c1']);
      expect(fallback.frames, hasLength(1));
      expect(fallback.stops, 1);
    });

    test('Release während des Token-Roundtrips startet P2P nicht nachträglich',
        () async {
      final primary =
          _RecordingPttRepository(startError: PttTokenException(503, 'x'));
      final repo = repoWith(primary);

      final start = repo.startTransmitting('c1');
      await repo.stopTransmitting();
      await start;

      expect(fallbackBuilds, 1, reason: 'Entscheidung bleibt gemerkt');
      expect(fallback.startedWith, isEmpty);
    });
  });

  group('FallbackPttRepository – Fehlerfälle', () {
    test('401 wird gemeldet, kein Fallback, nächster Druck versucht erneut',
        () async {
      final primary =
          _RecordingPttRepository(startError: PttTokenException(401, 'nope'));
      final repo = repoWith(primary);

      await expectLater(repo.startTransmitting('c1'), completes);
      await repo.startTransmitting('c1');
      await Future<void>.delayed(Duration.zero);

      expect(primary.startedWith, ['c1', 'c1'],
          reason: 'genau ein Versuch pro Tastendruck — kein Retry-Loop');
      expect(fallbackBuilds, 0);
      expect(
        reporter.errors.whereType<PttTokenException>().length,
        2,
        reason: 'Fehler via ObservabilityBootstrap gemeldet',
      );
    });

    test('unerwarteter Fehler wird gemeldet und nicht rethrown', () async {
      final primary =
          _RecordingPttRepository(startError: StateError('Verbindung kaputt'));
      final repo = repoWith(primary);

      await expectLater(repo.startTransmitting('c1'), completes);
      await Future<void>.delayed(Duration.zero);

      expect(fallbackBuilds, 0);
      expect(reporter.errors.whereType<StateError>(), hasLength(1));
    });

    test('sendFrame/stop ohne aktiven Transport sind No-ops', () async {
      final repo = repoWith(_RecordingPttRepository());

      expect(() => repo.sendFrame(Uint8List(1)), returnsNormally);
      await expectLater(repo.stopTransmitting(), completes);
    });
  });
}
