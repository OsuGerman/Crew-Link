import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart';

import 'ptt_repository.dart';
import 'ptt_token_fetcher.dart';

/// Minimaler Ausschnitt der LiveKit-Room-API, den PTT braucht.
/// Tests injizieren ein Fake-Handle statt einer echten SFU-Verbindung.
abstract interface class LiveKitRoomHandle {
  Future<void> setMicrophoneEnabled(bool enabled);

  /// Wird gerufen, wenn die Verbindung ENDGÜLTIG verloren ist — livekit_client
  /// hat seine internen Reconnect-Versuche erschöpft (engine.dart,
  /// `defaultRetryDelaysInMs`). Feuert nicht beim eigenen [close].
  set onDisconnected(void Function()? callback);

  /// Trennt die Verbindung und gibt native Ressourcen frei.
  Future<void> close();
}

/// Baut die Verbindung zu einem LiveKit-Raum auf.
typedef LiveKitRoomConnector = Future<LiveKitRoomHandle> Function(
  String url,
  String token,
);

/// Liefert das Room-Handle der geteilten Konvoi-Session.
/// `null` = Server ohne LiveKit-Konfiguration (P2P-Pfad zuständig);
/// wirft, wenn der Session-Aufbau fehlgeschlagen ist.
typedef LiveKitSessionResolver = Future<LiveKitRoomHandle?> Function(
  String convoyId,
);

/// Produktiv-Connector: echte [Room]-Verbindung über livekit_client.
Future<LiveKitRoomHandle> connectLiveKitRoom(String url, String token) async {
  final room = Room();
  await room.connect(url, token);
  return _RoomHandle(room);
}

class _RoomHandle implements LiveKitRoomHandle {
  _RoomHandle(this._room) {
    _listener = _room.createListener()
      ..on<RoomDisconnectedEvent>((event) {
        // clientInitiated = unser eigenes close() — kein Rejoin-Anlass.
        if (event.reason == DisconnectReason.clientInitiated) return;
        _onDisconnected?.call();
      });
  }

  final Room _room;
  late final EventsListener<RoomEvent> _listener;
  void Function()? _onDisconnected;

  @override
  set onDisconnected(void Function()? callback) => _onDisconnected = callback;

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room.localParticipant?.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> close() async {
    _onDisconnected = null;
    await _listener.dispose();
    await _room.disconnect();
    await _room.dispose();
  }
}

/// PTT-Sende-Pfad über die GETEILTE LiveKit-Session des Konvois
/// (livekitPttSessionProvider): [startTransmitting]/[stopTransmitting]
/// togglen nur noch das Mikrofon des bereits verbundenen Raums.
///
/// Gegenüber der Pro-Druck-Architektur entfallen damit Token-Fetch +
/// Raum-Connect bei jedem Tastendruck (Latenz) und die zweite Verbindung
/// derselben Identity (LiveKit kickt sonst die erste — Identity-Kick).
class LiveKitPttRepository implements PttRepository {
  LiveKitPttRepository({required LiveKitSessionResolver sessionResolver})
      : _resolveSession = sessionResolver;

  final LiveKitSessionResolver _resolveSession;

  /// Raum-Handle, solange der lokale Nutzer sendet (Mikro offen).
  LiveKitRoomHandle? _active;

  /// Generation des aktuellen Tastendrucks. Der Connect-Race der alten
  /// Architektur (Raum-Aufbau pro Druck) ist weg, weil der Raum beim Druck
  /// längst verbunden ist — aber das await auf den Session-AUFBAU (erster
  /// Druck direkt nach Konvoi-Eintritt) kann ein Release überholen; dann
  /// darf das Mikro nicht nachträglich angehen.
  int _generation = 0;

  @override
  Future<void> startTransmitting(String convoyId) async {
    if (_active != null) return; // sendet bereits — Doppel-Start ignorieren
    final generation = ++_generation;
    final room = await _resolveSession(convoyId);
    if (room == null) {
      // Transport-Entscheidung vom Konvoi-Eintritt: LiveKit nicht
      // konfiguriert. Gleiche Exception wie der direkte Token-Fetch, damit
      // FallbackPttRepository identisch umschaltet — ohne neuen Roundtrip.
      throw PttTokenException(
        pttLiveKitUnavailableStatus,
        'LiveKit nicht konfiguriert — Entscheidung beim Konvoi-Eintritt',
      );
    }
    if (generation != _generation) return; // Release während Session-Aufbau
    _active = room;
    await room.setMicrophoneEnabled(true);
    if (generation != _generation) {
      // Release kam an, während das Mikro noch anging — sofort wieder muten.
      await room.setMicrophoneEnabled(false);
    }
  }

  @override
  Future<void> stopTransmitting() async {
    _generation++;
    final room = _active;
    _active = null;
    if (room == null) return;
    // Nur muten — der Raum bleibt für Hörer-Seite und nächsten Druck offen.
    await room.setMicrophoneEnabled(false);
  }

  /// No-op: LiveKit published den Mikrofon-Track selbst — die Opus-Frames des
  /// PttChannel sind nur für den P2P-DataChannel-Pfad relevant.
  @override
  void sendFrame(Uint8List frame) {}
}
