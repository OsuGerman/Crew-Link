import 'dart:async';
import 'dart:typed_data';

import 'package:crew_link/features/push_to_talk/application/ptt_providers.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_channel.dart';
import 'package:crew_link/features/push_to_talk/domain/ptt_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Fake PttChannel that emits controllable frames.
class _FakePttChannel extends PttChannel {
  final _controller = StreamController<Uint8List>.broadcast();

  @override
  Future<void> startRecording() async {}

  @override
  Future<void> stopRecording() async {}

  @override
  Stream<Uint8List> get frames => _controller.stream;

  void emitFrame(Uint8List frame) => _controller.add(frame);

  @override
  // ignore: must_call_super
  void dispose() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('crewlink/ptt');

  void mockMethodChannel(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, handler);
  }

  setUp(() => mockMethodChannel((_) async => null));

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  group('PttChannel', () {
    test('startRecording invokes startRecording on the method channel',
        () async {
      final calls = <MethodCall>[];
      mockMethodChannel((call) async {
        calls.add(call);
        return null;
      });
      await PttChannel().startRecording();
      expect(calls.single.method, 'startRecording');
    });

    test('stopRecording invokes stopRecording on the method channel', () async {
      final calls = <MethodCall>[];
      mockMethodChannel((call) async {
        calls.add(call);
        return null;
      });
      await PttChannel().stopRecording();
      expect(calls.single.method, 'stopRecording');
    });
  });

  group('PttStateNotifier', () {
    ProviderContainer makeContainer() => ProviderContainer(
          overrides: [pttChannelProvider.overrideWith((_) => PttChannel())],
        );

    test('starts in idle state', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      expect(c.read(pttStateProvider), PttSessionState.idle);
    });

    test('transitions to transmitting on startTransmitting', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      await c.read(pttStateProvider.notifier).startTransmitting();
      expect(c.read(pttStateProvider), PttSessionState.transmitting);
    });

    test('transitions back to idle on stopTransmitting', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      await c.read(pttStateProvider.notifier).startTransmitting();
      await c.read(pttStateProvider.notifier).stopTransmitting();
      expect(c.read(pttStateProvider), PttSessionState.idle);
    });

    test('pttActiveProvider reflects transmitting state', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      expect(c.read(pttActiveProvider), isFalse);
      await c.read(pttStateProvider.notifier).startTransmitting();
      expect(c.read(pttActiveProvider), isTrue);
      await c.read(pttStateProvider.notifier).stopTransmitting();
      expect(c.read(pttActiveProvider), isFalse);
    });

    test('duplicate startTransmitting calls are idempotent', () async {
      final calls = <MethodCall>[];
      mockMethodChannel((call) async {
        calls.add(call);
        return null;
      });
      final c = makeContainer();
      addTearDown(c.dispose);
      await c.read(pttStateProvider.notifier).startTransmitting();
      await c.read(pttStateProvider.notifier).startTransmitting();
      expect(
        calls.where((m) => m.method == 'startRecording'),
        hasLength(1),
      );
    });
  });

  group('PttStateNotifier frame routing', () {
    late _FakePttChannel fake;
    late ProviderContainer container;

    setUp(() {
      fake = _FakePttChannel();
      container = ProviderContainer(
        overrides: [pttChannelProvider.overrideWith((_) => fake)],
      );
    });

    tearDown(() {
      container.dispose();
      fake.dispose();
    });

    test('onFrame callback receives frames while transmitting', () async {
      final received = <Uint8List>[];
      container.read(pttStateProvider.notifier).onFrame = received.add;

      await container.read(pttStateProvider.notifier).startTransmitting();

      final frame = Uint8List.fromList(List.filled(1920, 0));
      fake.emitFrame(frame);

      // Allow microtask queue to flush.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first, equals(frame));
    });

    test('onFrame is not called after stopTransmitting', () async {
      final received = <Uint8List>[];
      container.read(pttStateProvider.notifier).onFrame = received.add;

      await container.read(pttStateProvider.notifier).startTransmitting();
      await container.read(pttStateProvider.notifier).stopTransmitting();

      fake.emitFrame(Uint8List(1920));
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });
  });
}
