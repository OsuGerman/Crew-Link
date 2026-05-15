import 'dart:async';

import 'package:flutter/services.dart';

/// Dart side of the CarPlay MethodChannel. Mirrors the native side in
/// `ios/Runner/CarPlay/CarPlayBridge.swift`. Channel + method names MUST
/// stay in lock-step with the Swift constants.
///
/// The bridge is intentionally agnostic to who consumes the events — a
/// Riverpod provider in `convoy_providers.dart` will wire `pttEvents`
/// into the WebRTC capture session once that lands. Until then, the
/// stream is exposed for unit-testable verification only.
class CarPlayBridge {
  CarPlayBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handle);
  }

  static const String channelName = 'crewlink/carplay';

  final MethodChannel _channel;

  final StreamController<CarPlayEvent> _events =
      StreamController<CarPlayEvent>.broadcast();

  Stream<CarPlayEvent> get events => _events.stream;

  /// Pushes the current convoy state to the CarPlay map template's
  /// status header. No-op when not connected to CarPlay (CarPlay is
  /// what registers the handler; the call simply returns).
  Future<void> updateConvoyState({
    required int memberCount,
    required bool proximityActive,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateConvoyState', <String, Object>{
        'memberCount': memberCount,
        'proximityActive': proximityActive,
      });
    } on MissingPluginException {
      // CarPlay not connected — silently skip; the phone UI still has
      // the same state. Surfacing this would only spam the logger.
    }
  }

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'pttPressed':
        _events.add(const CarPlayEvent.pttPressed());
        return null;
      case 'pttReleased':
        _events.add(const CarPlayEvent.pttReleased());
        return null;
      default:
        throw MissingPluginException(
            'CarPlay channel: unknown method ${call.method}');
    }
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    if (!_events.isClosed) {
      await _events.close();
    }
  }
}

sealed class CarPlayEvent {
  const CarPlayEvent();
  const factory CarPlayEvent.pttPressed() = _PttPressed;
  const factory CarPlayEvent.pttReleased() = _PttReleased;
}

class _PttPressed extends CarPlayEvent {
  const _PttPressed();
  @override
  bool operator ==(Object other) => other is _PttPressed;
  @override
  int get hashCode => 0;
}

class _PttReleased extends CarPlayEvent {
  const _PttReleased();
  @override
  bool operator ==(Object other) => other is _PttReleased;
  @override
  int get hashCode => 1;
}
