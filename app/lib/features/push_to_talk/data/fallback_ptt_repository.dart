import 'dart:async';
import 'dart:typed_data';

import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';
import 'ptt_repository.dart';
import 'ptt_token_fetcher.dart';

/// Wählt den PTT-Transport zur Laufzeit:
///
/// * Standard ist [_primary] (LiveKit-SFU — funktioniert hinter CGNAT).
/// * Antwortet die Token-Route mit 503 (LiveKit-Env fehlt auf dem Server),
///   schaltet die App einmalig auf den P2P-WebRTC-Prototyp um; die
///   Entscheidung bleibt für die App-Laufzeit bestehen (kein Probe-Roundtrip
///   bei jedem weiteren Tastendruck).
/// * Andere Fehler (z. B. 401) werden geloggt + gemeldet und NICHT auf P2P
///   umgeleitet (das würde Auth-Bugs maskieren). Der nächste Tastendruck
///   versucht es erneut — es gibt keinen internen Retry-Loop.
///
/// Fehler werden hier geschluckt statt rethrown: der Aufrufer
/// (pttFrameRoutingProvider) awaitet [startTransmitting] in einem
/// ref.listen-Callback ohne eigenes Error-Handling.
class FallbackPttRepository implements PttRepository {
  FallbackPttRepository({
    required PttRepository primary,
    required PttRepository Function() fallbackBuilder,
  })  : _primary = primary,
        _fallbackBuilder = fallbackBuilder;

  final PttRepository _primary;

  /// Lazy: der P2P-Prototyp (braucht FirebaseDatabase.instance) wird erst
  /// instanziiert, wenn der Fallback tatsächlich gebraucht wird.
  final PttRepository Function() _fallbackBuilder;

  PttRepository? _fallback;
  PttRepository? _transmitting;

  /// Generation des aktuellen Tastendrucks: erkennt ein Release, das während
  /// des Token-Roundtrips passiert — dann wird der P2P-Pfad nicht mehr
  /// nachträglich gestartet.
  int _generation = 0;

  @override
  Future<void> startTransmitting(String convoyId) async {
    final generation = ++_generation;
    final active = _fallback ?? _primary;
    _transmitting = active;
    try {
      await active.startTransmitting(convoyId);
    } on PttTokenException catch (error, stack) {
      _transmitting = null;
      if (error.statusCode != pttLiveKitUnavailableStatus) {
        _report('PTT: LiveKit-Token-Route fehlgeschlagen', error, stack);
        return;
      }
      appLog.w('PTT-Fallback auf P2P-WebRTC — LiveKit nicht konfiguriert');
      final fallback = _fallback = _fallbackBuilder();
      if (generation != _generation) return;
      _transmitting = fallback;
      try {
        await fallback.startTransmitting(convoyId);
      } catch (error, stack) {
        _transmitting = null;
        _report('PTT: P2P-Fallback-Start fehlgeschlagen', error, stack);
      }
    } catch (error, stack) {
      _transmitting = null;
      _report('PTT: startTransmitting fehlgeschlagen', error, stack);
    }
  }

  @override
  Future<void> stopTransmitting() async {
    _generation++;
    final active = _transmitting;
    _transmitting = null;
    await active?.stopTransmitting();
  }

  /// Frames laufen nur in den gerade sendenden Transport; Frames vor dem
  /// Verbindungsaufbau verwirft der jeweilige Transport selbst (PTT-Semantik).
  @override
  void sendFrame(Uint8List frame) => _transmitting?.sendFrame(frame);

  void _report(String context, Object error, StackTrace stack) {
    appLog.e(context, error: error, stackTrace: stack);
    unawaited(ObservabilityBootstrap.build().reportError(error, stack));
  }
}
