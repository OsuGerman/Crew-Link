import 'package:crew_link/core/carplay/carplay_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The MethodChannel binds to ServicesBinding's default messenger,
  // which in test mode IS a TestDefaultBinaryMessenger. Going through
  // that singleton (instead of a freshly constructed wrapper) is the
  // only way setMockMethodCallHandler/handlePlatformMessage actually
  // reach the channel's handlers.
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(CarPlayBridge.channelName);

  group('CarPlayBridge', () {
    late CarPlayBridge bridge;
    final nativeCalls = <MethodCall>[];

    setUp(() {
      nativeCalls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call);
        return null;
      });
      bridge = CarPlayBridge(channel: channel);
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await bridge.dispose();
    });

    test('updateConvoyState forwards args to native', () async {
      await bridge.updateConvoyState(memberCount: 4, proximityActive: true);
      expect(nativeCalls, hasLength(1));
      expect(nativeCalls.single.method, 'updateConvoyState');
      expect(nativeCalls.single.arguments, {
        'memberCount': 4,
        'proximityActive': true,
      });
    });

    test('handles inbound pttPressed/pttReleased events from native',
        () async {
      final received = <CarPlayEvent>[];
      final sub = bridge.events.listen(received.add);
      addTearDown(sub.cancel);

      await _simulateNativeCall(messenger, 'pttPressed');
      await _simulateNativeCall(messenger, 'pttReleased');

      expect(received, [
        const CarPlayEvent.pttPressed(),
        const CarPlayEvent.pttReleased(),
      ]);
    });

    test(
        'updateConvoyState swallows MissingPluginException when CarPlay not connected',
        () async {
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        bridge.updateConvoyState(memberCount: 0, proximityActive: false),
        completes,
      );
    });
  });
}

Future<void> _simulateNativeCall(
  TestDefaultBinaryMessenger messenger,
  String method,
) async {
  const codec = StandardMethodCodec();
  final message = codec.encodeMethodCall(MethodCall(method));
  await messenger.handlePlatformMessage(
    CarPlayBridge.channelName,
    message,
    (data) {},
  );
}
