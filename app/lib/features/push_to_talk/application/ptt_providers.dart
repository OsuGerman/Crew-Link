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
import '../data/webrtc_ptt_receiver.dart';
import '../data/webrtc_ptt_repository.dart';
import '../domain/audio_session_event.dart';
import '../domain/ptt_session.dart';
import 'livekit_ptt_session.dart';

/// Injectable PttChannel – in Tests mit Fake überschreibbar.
final pttChannelProvider = Provider<PttChannel>((ref) => PttChannel());

/// P2P-WebRTC-Prototyp (nur STUN — scheitert hinter Carrier-Grade-NAT).
/// Seit der LiveKit-Umstellung nur noch Fallback ohne Server-Konfiguration.
final webrtcPttRepositoryProvider = Provider<PttRepository>((ref) {
  final userId = ref.watch(selfMemberIdProvider);
  return WebRtcDataChannelPttRepository(
    userId: userId,
    database: FirebaseDatabase.instance,
  );
});

/// PTT-Transport: Standard ist LiveKit (SFU, NAT-sicher) über die GETEILTE
/// Session aus [livekitPttSessionProvider] — die 503-Entscheidung fällt damit
/// beim Konvoi-Eintritt, nicht beim ersten Tastendruck. Ohne LiveKit-Env auf
/// dem Server schaltet [FallbackPttRepository] wie bisher sticky auf P2P um.
/// Typ PttRepository erlaubt Override mit Noop/Fake in Tests und Web-Preview.
final pttRepositoryProvider = Provider<PttRepository>((ref) {
  return FallbackPttRepository(
    primary: LiveKitPttRepository(
      sessionResolver: (convoyId) => resolveLiveKitPttSession(ref, convoyId),
    ),
    fallbackBuilder: () => ref.read(webrtcPttRepositoryProvider),
  );
});

/// Baut den P2P-Empfänger — Tests ersetzen die Factory, weil der echte
/// Receiver `FirebaseDatabase.instance` braucht (wirft ohne Firebase-Init).
final pttReceiverFactoryProvider =
    Provider<WebRtcPttReceiver Function(String convoyId, String localUserId)>(
  (ref) => (convoyId, localUserId) => WebRtcPttReceiver(
        convoyId: convoyId,
        localUserId: localUserId,
        database: FirebaseDatabase.instance,
      ),
);

/// Empfänger-Service für einen konkreten Konvoi-Stream (P2P-Pfad).
///
/// Startet [WebRtcPttReceiver.start] NUR, wenn die Transport-Entscheidung
/// vom Konvoi-Eintritt auf P2P gefallen ist (Token-Route 503): läuft die
/// geteilte LiveKit-Session, spielt livekit_client subscribed Remote-Audio
/// selbst ab — ein parallel lauschender P2P-Empfänger wäre doppeltes Audio.
/// Der minimal spätere Start (ein Token-Roundtrip) verpasst keine laufende
/// Übertragung: RTDB `onChildAdded` liefert auch bereits existierende
/// Sessions. autoDispose stoppt den Receiver beim Konvoi-Austritt.
final pttReceiverProvider =
    Provider.autoDispose.family<WebRtcPttReceiver, String>(
  (ref, convoyId) {
    final localUserId = ref.watch(selfMemberIdProvider);
    final receiver =
        ref.watch(pttReceiverFactoryProvider)(convoyId, localUserId);
    final useP2p = ref.watch(
      livekitPttSessionProvider(convoyId).select(
        (decision) => decision.valueOrNull?.usesP2pFallback ?? false,
      ),
    );
    if (useP2p) {
      receiver.start();
    }
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
/// Muss im aktiven Konvoi-Screen per convoyId gewatcht werden. autoDispose,
/// damit der gewatchte [pttReceiverProvider] beim Austritt abgebaut wird.
final pttPlaybackProvider =
    Provider.autoDispose.family<void, String>((ref, convoyId) {
  final receiver = ref.watch(pttReceiverProvider(convoyId));
  final channel = ref.watch(pttChannelProvider);
  final sub = receiver.frames.listen(channel.playFrame);
  ref.onDispose(() {
    sub.cancel();
    channel.stopPlayback();
  });
});

/// Verdrahtet Audio-Frames mit dem PTT-Repository wenn PTT aktiv ist.
/// Wird im aktiven Konvoi-Screen per convoyId gewatcht; autoDispose hält
/// die Lebensdauer konsistent mit Receiver/Playback/Session.
final pttFrameRoutingProvider =
    Provider.autoDispose.family<void, String>((ref, convoyId) {
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
