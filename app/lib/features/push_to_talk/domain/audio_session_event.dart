/// Audio session lifecycle events forwarded from iOS AVAudioSession
/// via the `crewlink/ptt/session` EventChannel.
enum AudioSessionEventType {
  interruptionBegan,
  interruptionEnded,
  bluetoothConnected,
  bluetoothDisconnected,
  unknown,
}

class AudioSessionEvent {
  const AudioSessionEvent(this.type, {this.shouldResume = false});

  factory AudioSessionEvent.fromMap(Map<String, Object?> map) {
    final type = map['type'] as String? ?? '';
    return switch (type) {
      'interruptionBegan' => const AudioSessionEvent(
          AudioSessionEventType.interruptionBegan,
        ),
      'interruptionEnded' => AudioSessionEvent(
          AudioSessionEventType.interruptionEnded,
          shouldResume: (map['shouldResume'] as bool?) ?? false,
        ),
      'bluetoothConnected' => const AudioSessionEvent(
          AudioSessionEventType.bluetoothConnected,
        ),
      'bluetoothDisconnected' => const AudioSessionEvent(
          AudioSessionEventType.bluetoothDisconnected,
        ),
      _ => const AudioSessionEvent(AudioSessionEventType.unknown),
    };
  }

  final AudioSessionEventType type;

  /// Only meaningful for [AudioSessionEventType.interruptionEnded].
  final bool shouldResume;
}
