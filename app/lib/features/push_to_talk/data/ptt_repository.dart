import 'dart:typed_data';

/// Abstraktion für WebRTC-Session-Management.
abstract interface class PttRepository {
  Future<void> startTransmitting(String convoyId);
  Future<void> stopTransmitting();

  /// Sendet einen Opus-Frame zum aktiven DataChannel.
  /// Frames vor Channel-Open werden verworfen (PTT-akzeptabel).
  void sendFrame(Uint8List frame);
}
