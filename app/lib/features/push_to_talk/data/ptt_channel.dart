import 'package:flutter/services.dart';

import '../domain/audio_session_event.dart';

/// Dart wrapper for the `crewlink/ptt` platform channel.
///
/// Native side: ios/Runner/PttAudioChannel.swift
///   startRecording — activates AVAudioEngine + Opus encoder (iOS 16+),
///                    falls back to raw int16 PCM on older OS.
///   stopRecording  — tears down the engine and deactivates AVAudioSession.
///   frames stream  — Opus packets or int16 PCM frames as raw bytes.
///   audioSessionEvents — interruption/BT route events from AVAudioSession.
class PttChannel {
  static const _method = MethodChannel('crewlink/ptt');
  static const _events = EventChannel('crewlink/ptt/frames');
  static const _sessionEventChannel = EventChannel('crewlink/ptt/session');

  Stream<Uint8List>? _frames;
  Stream<AudioSessionEvent>? _sessionEventsStream;

  Future<void> startRecording() => _method.invokeMethod('startRecording');
  Future<void> stopRecording() => _method.invokeMethod('stopRecording');
  Future<void> playFrame(Uint8List frame) =>
      _method.invokeMethod('playFrame', frame);
  Future<void> stopPlayback() => _method.invokeMethod('stopPlayback');

  /// Broadcast stream of encoded audio frames.
  /// Each element is one 20 ms Opus packet (960 samples) or raw int16 PCM.
  Stream<Uint8List> get frames {
    _frames ??= _events
        .receiveBroadcastStream()
        .map((dynamic e) => e as Uint8List);
    return _frames!;
  }

  /// Broadcast stream of AVAudioSession lifecycle events:
  /// interruptions (phone calls) and Bluetooth route changes.
  Stream<AudioSessionEvent> get audioSessionEvents {
    _sessionEventsStream ??= _sessionEventChannel
        .receiveBroadcastStream()
        .map((dynamic e) => AudioSessionEvent.fromMap(
              (e as Map).cast<String, Object?>(),
            ));
    return _sessionEventsStream!;
  }
}
