import 'dart:async';
import 'dart:typed_data';

import 'package:crew_link/core/carplay/carplay_bridge.dart';
import 'package:crew_link/core/carplay/carplay_providers.dart';
import 'package:crew_link/features/push_to_talk/application/ptt_providers.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_channel.dart';
import 'package:crew_link/features/push_to_talk/domain/ptt_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCarPlayBridge extends CarPlayBridge {
  _FakeCarPlayBridge()
      : super(
          channel: const MethodChannel('crewlink/carplay_fake'),
        );

  final _ctrl = StreamController<CarPlayEvent>.broadcast();

  @override
  Stream<CarPlayEvent> get events => _ctrl.stream;

  void emitPressed() => _ctrl.add(const CarPlayEvent.pttPressed());
  void emitReleased() => _ctrl.add(const CarPlayEvent.pttReleased());

  @override
  Future<void> dispose() async {
    await _ctrl.close();
    await super.dispose();
  }
}

class _FakePttChannel extends PttChannel {
  final _frames = StreamController<Uint8List>.broadcast();

  @override
  Future<void> startRecording() async {}

  @override
  Future<void> stopRecording() async {}

  @override
  Stream<Uint8List> get frames => _frames.stream;

  void dispose() => _frames.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('carPlayPttWiringProvider', () {
    late _FakeCarPlayBridge fakeBridge;
    late _FakePttChannel fakeChannel;
    late ProviderContainer container;

    setUp(() {
      fakeBridge = _FakeCarPlayBridge();
      fakeChannel = _FakePttChannel();
      container = ProviderContainer(
        overrides: [
          carPlayBridgeProvider.overrideWithValue(fakeBridge),
          pttChannelProvider.overrideWithValue(fakeChannel),
        ],
      );
      // Activate wiring subscription.
      container.listen(carPlayPttWiringProvider, (_, __) {});
    });

    tearDown(() async {
      container.dispose();
      await fakeBridge.dispose();
      fakeChannel.dispose();
    });

    test('pttPressed event transitions state to transmitting', () async {
      fakeBridge.emitPressed();
      // Allow microtask queue to drain.
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(pttStateProvider),
        PttSessionState.transmitting,
      );
    });

    test('pttReleased after pressed transitions back to idle', () async {
      fakeBridge.emitPressed();
      await Future<void>.delayed(Duration.zero);
      fakeBridge.emitReleased();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pttStateProvider), PttSessionState.idle);
    });

    test('pttReleased without prior pressed stays idle', () async {
      fakeBridge.emitReleased();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pttStateProvider), PttSessionState.idle);
    });
  });
}
