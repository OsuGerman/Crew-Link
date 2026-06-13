import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';
import '../../convoy/application/convoy_providers.dart';
import '../data/livekit_ptt_repository.dart';
import '../data/ptt_token_fetcher.dart';

/// Versuche für den initialen Raum-Join (inklusive Erstversuch).
const _maxJoinAttempts = 3;

/// Wartezeit vor dem n-ten Wiederholungsversuch (linear ansteigend: 2 s, 4 s).
/// livekit_client reconnected eine BESTEHENDE Verbindung selbst (engine.dart,
/// `defaultRetryDelaysInMs`) — dieser Backoff deckt nur den initialen Join ab
/// (z. B. Funkloch beim Konvoi-Eintritt).
const _joinBackoffBase = Duration(seconds: 2);

/// HTTP-Status ab dem ein Token-Fehler als transient gilt (5xx, z. B.
/// Render-Neustart). 4xx (401/403) sind Auth-/Client-Fehler — Retries
/// würden sie nur maskieren.
const _httpServerErrorFloor = 500;

/// Wartet zwischen Join-Versuchen — Tests injizieren einen No-op.
typedef JoinDelay = Future<void> Function(Duration delay);

/// Holt LiveKit-Tokens von der Backend-Route — gleiche Base-URL und Auth wie
/// die übrigen REST-Calls (frischer Firebase-ID-Token pro Anfrage).
final pttTokenFetcherProvider = Provider<PttTokenFetcher>((ref) {
  return PttTokenFetcher(
    config: ref.watch(apiConfigProvider),
    tokenProvider: ref.watch(freshAuthTokenProvider),
    client: ref.watch(httpClientProvider),
  );
});

/// Produktiv-Verbindung zur LiveKit-SFU — Tests injizieren einen Fake,
/// damit kein echter Raum betreten wird.
final livekitRoomConnectorProvider =
    Provider<LiveKitRoomConnector>((ref) => connectLiveKitRoom);

/// Transport-Entscheidung beim Konvoi-Eintritt (Antwort der Token-Route).
class PttTransportDecision {
  const PttTransportDecision.liveKit(LiveKitRoomHandle this.room);
  const PttTransportDecision.p2pFallback() : room = null;

  /// Verbundenes (gemutetes) Room-Handle — `null` heißt: LiveKit ist auf dem
  /// Server nicht konfiguriert (503), der P2P-Pfad bleibt zuständig.
  final LiveKitRoomHandle? room;

  bool get usesP2pFallback => room == null;
}

/// Geteilte LiveKit-Room-Session für die Dauer des Konvois — EIN gemuteter
/// Join beim Eintritt statt Connect pro Tastendruck.
///
/// Hörer-Seite: livekit_client abonniert Remote-Tracks automatisch
/// (`ConnectOptions.autoSubscribe` = true) und startet subscribed
/// Audio-Tracks selbst (RemoteParticipant ruft nach der Subscription
/// `track.start()`; auf iOS/Android routet flutter_webrtc empfangenes Audio
/// direkt auf den Geräte-Output — `audio.startAudio` ist reiner Web-Support).
/// Es ist also kein eigener Player nötig; verifiziert in livekit_client 2.4.1.
///
/// Lifecycle: Join beim Konvoi-Eintritt (Watch in der ActiveConvoyView),
/// Disconnect beim Austritt (autoDispose). Bei endgültigem Verbindungsverlust
/// baut [LiveKitRoomHandle.onDisconnected] → `invalidateSelf` die Session neu
/// auf (inklusive Backoff-Retry des Joins).
final livekitPttSessionProvider = FutureProvider.autoDispose
    .family<PttTransportDecision, String>((ref, convoyId) async {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final decision = await joinLiveKitPttSession(
    convoyId: convoyId,
    tokenFetcher: ref.watch(pttTokenFetcherProvider),
    connector: ref.watch(livekitRoomConnectorProvider),
  );
  final room = decision.room;
  if (room == null) return decision;
  if (disposed) {
    // Konvoi-Austritt während des Joins — Raum nicht offen liegen lassen.
    unawaited(room.close());
    return decision;
  }
  room.onDisconnected = ref.invalidateSelf;
  ref.onDispose(() {
    room.onDisconnected = null;
    unawaited(room.close());
  });
  return decision;
});

/// Room-Handle der geteilten Session für den Sende-Pfad
/// ([LiveKitPttRepository]). Voraussetzung: die ActiveConvoyView watcht
/// [livekitPttSessionProvider] (Join beim Konvoi-Eintritt) — sonst würde der
/// autoDispose-Provider direkt nach dem read wieder abgebaut.
Future<LiveKitRoomHandle?> resolveLiveKitPttSession(
  Ref ref,
  String convoyId,
) async {
  if (ref.read(livekitPttSessionProvider(convoyId)) is AsyncError) {
    // Fehlgeschlagener Session-Aufbau: genau ein neuer Anlauf pro Tastendruck
    // (gleicher Kontrakt wie vor dem geteilten Raum — kein Retry-Loop).
    ref.invalidate(livekitPttSessionProvider(convoyId));
  }
  final decision =
      await ref.read(livekitPttSessionProvider(convoyId).future);
  return decision.room;
}

/// Baut die geteilte Session auf: Token holen, Raum GEMUTET betreten.
///
/// * 503 der Token-Route → [PttTransportDecision.p2pFallback] (kein Join,
///   der P2P-Pfad inklusive RTDB-Receiver bleibt wie bisher zuständig).
/// * Transiente Fehler (Netz/Connect/5xx) → Backoff-Retry, danach melden.
/// * 4xx (z. B. 401) → sofort melden, kein Retry (Auth-Bugs nicht maskieren).
Future<PttTransportDecision> joinLiveKitPttSession({
  required String convoyId,
  required PttTokenFetcher tokenFetcher,
  required LiveKitRoomConnector connector,
  JoinDelay? delay,
}) async {
  final wait = delay ?? Future<void>.delayed;
  for (var attempt = 1; ; attempt++) {
    try {
      final grant = await tokenFetcher.fetchToken(convoyId);
      final room = await connector(grant.url, grant.token);
      try {
        // Explizit gemutet beitreten: gesendet wird erst beim PTT-Druck.
        await room.setMicrophoneEnabled(false);
      } catch (_) {
        // Kein Schlucken (rethrow → äußerer Handler meldet) — nur den Raum
        // nicht offen liegen lassen (Identity-Kick beim nächsten Versuch).
        await room.close();
        rethrow;
      }
      return PttTransportDecision.liveKit(room);
    } catch (error, stack) {
      if (error is PttTokenException &&
          error.statusCode == pttLiveKitUnavailableStatus) {
        appLog.w('PTT: LiveKit nicht konfiguriert (503) — P2P-Pfad aktiv');
        return const PttTransportDecision.p2pFallback();
      }
      final transient = error is! PttTokenException ||
          error.statusCode >= _httpServerErrorFloor;
      if (!transient || attempt >= _maxJoinAttempts) {
        appLog.e(
          'PTT: LiveKit-Session-Aufbau fehlgeschlagen',
          error: error,
          stackTrace: stack,
        );
        unawaited(ObservabilityBootstrap.build().reportError(error, stack));
        rethrow;
      }
      await wait(_joinBackoffBase * attempt);
    }
  }
}
