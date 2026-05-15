import 'dart:async';
import 'dart:typed_data';

import 'package:crew_link/features/push_to_talk/application/ptt_providers.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_channel.dart';
import 'package:crew_link/features/push_to_talk/domain/audio_session_event.dart';
import 'package:crew_link/features/push_to_talk/domain/ptt_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

class _FakePttChannel extends PttChannel {
  final _sessionCtrl = StreamController<AudioSessionEvent>.broadcast();

  @override
  Stream<AudioSessionEvent> get audioSessionEvents => _sessionCtrl.stream;

  @override
  Future<void> startRecording() async {}

  @override
  Future<void> stopRecording() async {}

  @override
  Future<void> playFrame(Uint8List frame) async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Stream<Uint8List> get frames => const Stream.empty();

  void emit(AudioSessionEvent event) => _sessionCtrl.add(event);

  void closeStream() => _sessionCtrl.close();
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

ProviderContainer _container(_FakePttChannel fake) => ProviderContainer(
      overrides: [pttChannelProvider.overrideWithValue(fake)],
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PttStateNotifier – audio session handling', () {
    late _FakePttChannel fake;
    late ProviderContainer container;

    setUp(() {
      fake = _FakePttChannel();
      container = _container(fake);
    });

    tearDown(() {
      fake.closeStream();
      container.dispose();
    });

    test('interruptionBegan stops transmitting', () async {
      await container.read(pttStateProvider.notifier).startTransmitting();
      expect(container.read(pttStateProvider), PttSessionState.transmitting);

      fake.emit(
        const AudioSessionEvent(AudioSessionEventType.interruptionBegan),
      );

      // Drain the async chain inside stopTransmitting().
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(pttStateProvider), PttSessionState.idle);
    });

    test('interruptionEnded does not auto-resume transmitting', () async {
      // Ensure we are idle before the ended event.
      fake.emit(
        const AudioSessionEvent(
          AudioSessionEventType.interruptionEnded,
          shouldResume: true,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(container.read(pttStateProvider), PttSessionState.idle);
    });

    test('bluetoothConnected event does not change transmit state', () async {
      fake.emit(
        const AudioSessionEvent(AudioSessionEventType.bluetoothConnected),
      );

      await Future<void>.delayed(Duration.zero);

      expect(container.read(pttStateProvider), PttSessionState.idle);
    });

    test('interruptionBegan while idle does not throw', () async {
      expect(container.read(pttStateProvider), PttSessionState.idle);

      expect(
        () => fake.emit(
          const AudioSessionEvent(AudioSessionEventType.interruptionBegan),
        ),
        returnsNormally,
      );

      await Future<void>.delayed(Duration.zero);
      expect(container.read(pttStateProvider), PttSessionState.idle);
    });
  });

  group('AudioSessionEvent.fromMap', () {
    test('parses interruptionBegan', () {
      final event = AudioSessionEvent.fromMap({'type': 'interruptionBegan'});
      expect(event.type, AudioSessionEventType.interruptionBegan);
      expect(event.shouldResume, isFalse);
    });

    test('parses interruptionEnded with shouldResume', () {
      final event = AudioSessionEvent.fromMap({
        'type': 'interruptionEnded',
        'shouldResume': true,
      });
      expect(event.type, AudioSessionEventType.interruptionEnded);
      expect(event.shouldResume, isTrue);
    });

    test('parses bluetoothConnected', () {
      final event = AudioSessionEvent.fromMap({'type': 'bluetoothConnected'});
      expect(event.type, AudioSessionEventType.bluetoothConnected);
    });

    test('parses bluetoothDisconnected', () {
      final event =
          AudioSessionEvent.fromMap({'type': 'bluetoothDisconnected'});
      expect(event.type, AudioSessionEventType.bluetoothDisconnected);
    });

    test('unknown type maps to AudioSessionEventType.unknown', () {
      final event = AudioSessionEvent.fromMap({'type': 'someFutureEvent'});
      expect(event.type, AudioSessionEventType.unknown);
    });
  });
}
