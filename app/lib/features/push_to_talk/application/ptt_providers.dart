import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';
import '../../../features/convoy/application/convoy_providers.dart';
import '../data/fallback_ptt_repository.dart';
import '../data/livekit_ptt_repository.dart';
import '../data/ptt_channel.dart';
import '../data/ptt_repository.dart';
import '../data/ptt_token_fetcher.dart';
import '../data/webrtc_ptt_receiver.dart';
import '../data/webrtc_ptt_repository.dart';
import '../domain/audio_session_event.dart';
import '../domain/ptt_session.dart';

/// Injectable PttChannel – in Tests mit Fake überschreibbar.
final pttChannelProvider = Provider<PttChannel>((ref) => PttChannel());

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

/// P2P-WebRTC-Prototyp (nur STUN — scheitert hinter Carrier-Grade-NAT).
/// Seit der LiveKit-Umstellung nur noch Fallback ohne Server-Konfiguration.
final webrtcPttRepositoryProvider = Provider<PttRepository>((ref) {
  final userId = ref.watch(selfMemberIdProvider);
  return WebRtcDataChannelPttRepository(
    userId: userId,
    database: FirebaseDatabase.instance,
  );
});

/// PTT-Transport: Standard ist LiveKit (SFU, NAT-sicher). Liefert die
/// Token-Route 503 (LiveKit-Env fehlt auf dem Server), fällt die App auf den
/// P2P-WebRTC-Pfad zurück — siehe [FallbackPttRepository].
/// Typ PttRepository erlaubt Override mit Noop/Fake in Tests und Web-Preview.
final pttRepositoryProvider = Provider<PttRepository>((ref) {
  return FallbackPttRepository(
    primary: LiveKitPttRepository(
      tokenFetcher: ref.watch(pttTokenFetcherProvider),
      connector: ref.watch(livekitRoomConnectorProvider),
    ),
    fallbackBuilder: () => ref.read(webrtcPttRepositoryProvider),
  );
});

/// Empfänger-Service für einen konkreten Konvoi-Stream.
/// Startet [WebRtcPttReceiver.start] automatisch und stoppt bei Dispose.
final pttReceiverProvider = Provider.family<WebRtcPttReceiver, String>(
  (ref, convoyId) {
    final localUserId = ref.watch(selfMemberIdProvider);
    final receiver = WebRtcPttReceiver(
      convoyId: convoyId,
      localUserId: localUserId,
      database: FirebaseDatabase.instance,
    );
    receiver.start();
    ref.onDispose(receiver.stop);
    return receiver;
  },
);

final pttStateProvider =
    StateNotifierProvider<PttStateNotifier, PttSessionState>(
  (ref) => PttStateNotifier(channel: ref.watch(pttChannelProvider)),
);

/// True solange der lokale Nutzer sendet.
final pttActiveProvider = Provider<bool>(
  (ref) => ref.watch(pttStateProvider) == PttSessionState.transmitting,
);

/// Leitet empfangene Opus-Frames vom Receiver an den nativen Playback-Kanal.
/// Muss im aktiven Konvoi-Screen per convoyId gewatcht werden.
final pttPlaybackProvider = Provider.family<void, String>((ref, convoyId) {
  final receiver = ref.watch(pttReceiverProvider(convoyId));
  final channel = ref.watch(pttChannelProvider);
  final sub = receiver.frames.listen(channel.playFrame);
  ref.onDispose(() {
    sub.cancel();
    channel.stopPlayback();
  });
});

/// Verdrahtet Audio-Frames mit dem WebRTC-Repository wenn PTT aktiv ist.
/// Wird im aktiven Konvoi-Screen per convoyId gewatcht.
final pttFrameRoutingProvider = Provider.family<void, String>((ref, convoyId) {
  final repository = ref.watch(pttRepositoryProvider);
  final notifier = ref.read(pttStateProvider.notifier);

  ref.listen<PttSessionState>(pttStateProvider, (_, state) async {
    if (state == PttSessionState.transmitting) {
      notifier.onFrame = repository.sendFrame;
      await repository.startTransmitting(convoyId);
    } else {
      notifier.onFrame = null;
      await repository.stopTransmitting();
    }
  });
});

class PttStateNotifier extends StateNotifier<PttSessionState> {
  PttStateNotifier({required PttChannel channel})
      : _channel = channel,
        super(PttSessionState.idle) {
    _sessionSub = channel.audioSessionEvents.listen(_onSessionEvent);
  }

  final PttChannel _channel;
  StreamSubscription<Uint8List>? _framesSub;
  StreamSubscription<AudioSessionEvent>? _sessionSub;

  /// Callback für jeden eingehenden Opus-Frame (z. B. WebRTC-Send oder Playback).
  void Function(Uint8List)? onFrame;

  Future<void> startTransmitting() async {
    if (state == PttSessionState.transmitting) return;
    state = PttSessionState.transmitting;
    try {
      await _channel.startRecording();
      _framesSub = _channel.frames.listen((frame) => onFrame?.call(frame));
    } catch (error, stack) {
      state = PttSessionState.idle;
      appLog.e('PttStateNotifier.startTransmitting', error: error, stackTrace: stack);
      unawaited(ObservabilityBootstrap.build().reportError(error, stack));
      rethrow;
    }
  }

  Future<void> stopTransmitting() async {
    if (state != PttSessionState.transmitting) return;
    await _framesSub?.cancel();
    _framesSub = null;
    await _channel.stopRecording();
    state = PttSessionState.idle;
  }

  void _onSessionEvent(AudioSessionEvent event) {
    if (event.type == AudioSessionEventType.interruptionBegan) {
      unawaited(stopTransmitting());
    }
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }
}
