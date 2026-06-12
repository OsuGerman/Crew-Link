import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart';

import 'ptt_repository.dart';
import 'ptt_token_fetcher.dart';

/// Minimaler Ausschnitt der LiveKit-Room-API, den das Repository braucht.
/// Tests injizieren ein Fake-Handle statt einer echten SFU-Verbindung.
abstract interface class LiveKitRoomHandle {
  Future<void> setMicrophoneEnabled(bool enabled);

  /// Trennt die Verbindung und gibt native Ressourcen frei.
  Future<void> close();
}

/// Baut die Verbindung zu einem LiveKit-Raum auf.
typedef LiveKitRoomConnector = Future<LiveKitRoomHandle> Function(
  String url,
  String token,
);

/// Produktiv-Connector: echte [Room]-Verbindung über livekit_client.
Future<LiveKitRoomHandle> connectLiveKitRoom(String url, String token) async {
  final room = Room();
  await room.connect(url, token);
  return _RoomHandle(room);
}

class _RoomHandle implements LiveKitRoomHandle {
  _RoomHandle(this._room);

  final Room _room;

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room.localParticipant?.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> close() async {
    await _room.disconnect();
    await _room.dispose();
  }
}

/// PTT-Transport über LiveKit (SFU): funktioniert hinter Carrier-Grade-NAT,
/// weil Audio über den Server läuft — kein P2P-Hole-Punching nötig.
///
/// Pro Transmission wird ein frisches Token geholt und der Raum betreten;
/// [stopTransmitting] trennt wieder. Audio-Encoding übernimmt LiveKit intern.
class LiveKitPttRepository implements PttRepository {
  LiveKitPttRepository({
    required PttTokenFetcher tokenFetcher,
    LiveKitRoomConnector connector = connectLiveKitRoom,
  })  : _tokenFetcher = tokenFetcher,
        _connector = connector;

  final PttTokenFetcher _tokenFetcher;
  final LiveKitRoomConnector _connector;

  LiveKitRoomHandle? _room;

  /// Generation des aktuellen Tastendrucks: erkennt ein Release das während
  /// Token-Fetch/Verbindungsaufbau passiert — sonst bliebe ein offenes Mikro
  /// im Raum zurück (Kurz-Tap ist der häufigste Fall im Feld).
  int _session = 0;

  @override
  Future<void> startTransmitting(String convoyId) async {
    if (_room != null) return; // bereits verbunden — Doppel-Start ignorieren
    final session = ++_session;
    final grant = await _tokenFetcher.fetchToken(convoyId);
    final room = await _connector(grant.url, grant.token);
    if (session != _session) {
      // Taste wurde während des Aufbaus losgelassen — sofort wieder abbauen.
      await room.close();
      return;
    }
    // Handle VOR dem Mikrofon-Start merken: schlägt setMicrophoneEnabled
    // fehl (z. B. Berechtigung), räumt stopTransmitting trotzdem auf.
    _room = room;
    await room.setMicrophoneEnabled(true);
  }

  @override
  Future<void> stopTransmitting() async {
    _session++;
    final room = _room;
    _room = null;
    if (room == null) return;
    await room.setMicrophoneEnabled(false);
    await room.close();
  }

  /// No-op: LiveKit published den Mikrofon-Track selbst — die Opus-Frames des
  /// PttChannel sind nur für den P2P-DataChannel-Pfad relevant.
  @override
  void sendFrame(Uint8List frame) {}
}
