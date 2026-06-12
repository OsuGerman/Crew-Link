import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/convoy/domain/quick_action.dart';
import '../../features/convoy/domain/waypoint.dart';
import '../../features/convoy/domain/waypoint_check_in.dart';
import '../../features/convoy/domain/waypoint_tour.dart';
import '../config/api_config.dart';
import '../models/gps_update.dart';
import '../models/hazard_report.dart';
import '../observability/app_logger.dart';
import '../observability/observability_bootstrap.dart';
import 'connection_status.dart';
import 'hazard_event.dart';
import 'inbound_frame_decoder.dart';
import 'outbound_frame_queue.dart';

/// Factory for opening a WebSocket. Defaults to the real
/// `WebSocketChannel.connect`; tests inject a fake to drive failure /
/// success scenarios without a server.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

/// One persistent WebSocket channel per convoy.
///
/// Rule: GPS updates flow exclusively through this WebSocket channel;
/// REST is reserved for CRUD on convoys/profiles. No polling fallback.
///
/// Resilience: the client transparently reconnects on network loss with
/// exponential backoff (`baseRetryDelay * 2^attempt`, capped at
/// `maxRetryDelay`) plus ±25% jitter to avoid thundering-herd reconnects
/// when a tower comes back online with many cars on the same convoy.
/// Reconnect attempts continue until `disconnect()` is called. Every
/// (re)connect fetches a FRESH auth token via [tokenProvider], and critical
/// frames published while offline are buffered in an [OutboundFrameQueue]
/// and flushed in original order after the next successful connect.
class ConvoySocketClient {
  ConvoySocketClient({
    required this.config,
    required this.convoyId,
    required this.tokenProvider,
    WebSocketChannelFactory? channelFactory,
    Duration baseRetryDelay = const Duration(seconds: 1),
    Duration maxRetryDelay = const Duration(seconds: 30),
    math.Random? random,
  })  : _channelFactory = channelFactory ?? WebSocketChannel.connect,
        _baseRetryDelay = baseRetryDelay,
        _maxRetryDelay = maxRetryDelay,
        _random = random ?? math.Random();

  final ApiConfig config;
  final String convoyId;

  /// Liefert pro Connect-Versuch einen FRISCHEN Auth-Token. Firebase-ID-
  /// Tokens laufen nach ~1 h ab — ein einmalig eingefrorener Token-String
  /// würde jeden späteren Reconnect in eine 401-Endlosschleife schicken.
  /// `User.getIdToken()` erneuert abgelaufene Tokens transparent.
  final Future<String> Function() tokenProvider;

  final WebSocketChannelFactory _channelFactory;
  final Duration _baseRetryDelay;
  final Duration _maxRetryDelay;
  final math.Random _random;

  static const int _backoffExponentCap = 5;
  static const double _jitterFraction = 0.25;

  /// Watchdog gegen halbtote Verbindungen (Funkloch, NAT-Timeout): Status
  /// bleibt "connected", aber es kommt nichts mehr an.
  ///
  /// Entscheidung (robusteste Variante OHNE Backend-Änderung — Stand
  /// backend/src/realtime/convoy_gateway.ts):
  /// • Der Server erzeugt KEINEN periodischen App-Level-Traffic; Inbound-
  ///   Frames entstehen nur aus dem Connect-Snapshot und dem Fanout der
  ///   anderen Mitglieder.
  /// • Der Server pingt PROTOKOLL-Level alle 25 s (backend heartbeat.ts,
  ///   daher 35 s > 25 s) — Protokoll-Pings beantwortet die Dart-Runtime
  ///   transparent, sie sind hier NICHT als Frames sichtbar und können den
  ///   Watchdog nicht füttern.
  /// • Ein App-Level-Self-Ping hätte kein Echo: der Fanout schließt den
  ///   Sender aus, unbekannte Frame-Typen verwirft das Server-Schema.
  /// ⇒ Der Watchdog koppelt an ausbleibende App-Frames, wird aber erst
  ///   SCHARF, sobald auf der AKTUELLEN Verbindung mindestens ein Frame
  ///   ankam: aktive Konvois liefern Peer-GPS mit ≥ 0,2 Hz (5-s-Park-
  ///   intervall), 35 s Stille heißt dort "Leitung tot" → Reconnect.
  ///   Stille Solo-Konvois (kein erwartbarer Inbound) zyklieren so nicht
  ///   alle 35 s durch sinnlose Reconnects.
  static const Duration kInboundSilenceTimeout = Duration(seconds: 35);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _frameSub;
  Timer? _reconnectTimer;
  Timer? _inboundWatchdog;
  int _retryAttempt = 0;
  bool _disposed = false;
  ConnectionStatus _currentStatus = ConnectionStatus.connecting;
  final OutboundFrameQueue _outboundQueue = OutboundFrameQueue();

  final StreamController<GpsUpdate> _gpsController =
      StreamController<GpsUpdate>.broadcast();
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<Waypoint?> _waypointController =
      StreamController<Waypoint?>.broadcast();
  final StreamController<HazardEvent> _hazardController =
      StreamController<HazardEvent>.broadcast();
  final StreamController<WaypointTour> _tourController =
      StreamController<WaypointTour>.broadcast();
  final StreamController<WaypointCheckIn> _checkInController =
      StreamController<WaypointCheckIn>.broadcast();
  final StreamController<QuickAction> _quickActionController =
      StreamController<QuickAction>.broadcast();

  Stream<GpsUpdate> get gpsUpdates => _gpsController.stream;
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;
  /// Inbound waypoint updates from the convoy WebSocket. Emits `null` when
  /// the leader clears the waypoint. Last value is NOT replayed — UI
  /// subscribes early via the convoy session.
  Stream<Waypoint?> get waypointUpdates => _waypointController.stream;
  /// Inbound hazard-pin life-cycle events (added / removed).
  Stream<HazardEvent> get hazardEvents => _hazardController.stream;
  /// Inbound Routenplan-Updates. Volle State-Snapshots (kein delta).
  Stream<WaypointTour> get tourUpdates => _tourController.stream;
  /// Inbound Check-Ins — Mitglieder die einen Tour-Stopp erreicht haben.
  Stream<WaypointCheckIn> get checkIns => _checkInController.stream;
  /// Inbound One-Tap-Schnellaktionen (Pause/Tankstopp/…) anderer Mitglieder.
  Stream<QuickAction> get quickActions => _quickActionController.stream;
  ConnectionStatus get currentStatus => _currentStatus;

  Future<void> connect() async {
    _disposed = false;
    await _attemptConnect();
  }

  Future<void> _attemptConnect() async {
    if (_disposed) return;
    _setStatus(ConnectionStatus.connecting);
    final String token;
    try {
      token = await tokenProvider();
    } catch (error, stack) {
      appLog.e('ConvoySocketClient: Token-Beschaffung fehlgeschlagen',
          error: error, stackTrace: stack);
      unawaited(ObservabilityBootstrap.build().reportError(error, stack));
      _onChannelLost();
      return;
    }
    if (_disposed) return;
    final endpoint = config.wsBaseUrl.replace(
      path: '/convoys/$convoyId/stream',
      queryParameters: {'token': token},
    );
    try {
      final channel = _channelFactory(endpoint);
      await channel.ready;
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _retryAttempt = 0;
      _setStatus(ConnectionStatus.connected);
      _frameSub = channel.stream.listen(
        _handleFrame,
        onError: (Object err, StackTrace _) {
          if (!_gpsController.isClosed) _gpsController.addError(err);
          _onChannelLost();
        },
        onDone: _onChannelLost,
        cancelOnError: false,
      );
      // Während der Offline-Phase gepufferte kritische Frames (SOS!,
      // hazard_remove, waypoint, tour) in Originalreihenfolge nachsenden.
      for (final frame in _outboundQueue.drain()) {
        channel.sink.add(frame);
      }
    } catch (_) {
      _onChannelLost();
    }
  }

  void _onChannelLost() {
    _inboundWatchdog?.cancel();
    _inboundWatchdog = null;
    _frameSub?.cancel();
    _frameSub = null;
    _channel = null;
    if (_disposed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _retryAttempt += 1;
    final exponent = math.min(_retryAttempt - 1, _backoffExponentCap);
    final base = _baseRetryDelay * (1 << exponent);
    final capped = base > _maxRetryDelay ? _maxRetryDelay : base;
    final jitterMs = (capped.inMilliseconds *
            _jitterFraction *
            (_random.nextDouble() * 2 - 1))
        .round();
    final delay = capped + Duration(milliseconds: jitterMs);
    _setStatus(ConnectionStatus.reconnecting);
    _reconnectTimer = Timer(delay, () {
      unawaited(_attemptConnect());
    });
  }

  /// (Re-)startet den Inbound-Watchdog — siehe [kInboundSilenceTimeout].
  void _restartInboundWatchdog() {
    _inboundWatchdog?.cancel();
    _inboundWatchdog = Timer(kInboundSilenceTimeout, _onInboundSilence);
  }

  /// 35 s ohne Inbound-Frame auf einer Verbindung, die schon Frames
  /// geliefert hat → Leitung gilt als halbtot, normaler Reconnect greift.
  void _onInboundSilence() {
    if (_disposed || _currentStatus != ConnectionStatus.connected) return;
    unawaited(_channel?.sink.close());
    _onChannelLost();
  }

  /// Best-effort publish. Silently drops the frame when the socket is
  /// not currently connected — GPS is a fire-and-forget firehose where
  /// the next 1 Hz tick carries a fresher position anyway. Lossy-critical
  /// payloads (SOS/hazard, waypoint, tour) go through [_sendCritical]
  /// with offline buffering instead.
  void publishLocation(GpsUpdate update) {
    final sink = _channel?.sink;
    if (sink == null) return;
    sink.add(jsonEncode({'type': 'gps', 'payload': update.toJson()}));
  }

  /// Publisht den Waypoint. `null` löscht den aktuellen Pin. Kritischer
  /// Frame: wird ohne Verbindung gepuffert und nach dem Reconnect in
  /// Originalreihenfolge nachgesendet (Empfänger sind last-wins).
  void publishWaypoint(Waypoint? waypoint) {
    _sendCritical({'type': 'waypoint', 'payload': waypoint?.toJson()});
  }

  /// Publisht eine Gefahrenmeldung (inkl. SOS) an alle Konvoi-Mitglieder.
  /// Hazards sind „add-only" auf der Wire — Cleanup läuft client-seitig via
  /// `expiresAt` Auto-Prune und explizitem `publishHazardRemoval`. Kritischer
  /// Frame: niemals still verwerfen, sondern offline puffern.
  void publishHazardReport(HazardReport report) {
    _sendCritical({'type': 'hazard', 'payload': report.toJson()});
  }

  /// Entfernt eine Gefahrenmeldung bei allen Mitgliedern. Der Server
  /// validiert dass der `reporterId`-Feldwert des Hazards mit dem
  /// authenticated sender übereinstimmt (nur Reporter darf entfernen).
  void publishHazardRemoval(String hazardId) {
    _sendCritical({
      'type': 'hazard_remove',
      'payload': {'id': hazardId},
    });
  }

  /// Veröffentlicht den kompletten Tour-Plan (Reihenfolge der Stopps) an
  /// alle Konvoi-Mitglieder. Bewusst Full-State statt Delta — Tour-Edits
  /// sind selten genug und last-wins ist robuster bei verlorenen Frames.
  /// Kritischer Frame: wird offline gepuffert statt verworfen.
  void publishTour(WaypointTour tour) {
    _sendCritical({'type': 'tour', 'payload': tour.toJson()});
  }

  /// Publisht eine Check-In-Bestätigung für einen Tour-Stopp. Identifiziert
  /// den Stopp via `stopSignature` damit alte Check-Ins von vergangenen
  /// Stopps nicht mit dem aktuellen Head vermischt werden.
  void publishCheckIn(WaypointCheckIn checkIn) {
    final sink = _channel?.sink;
    if (sink == null) return;
    sink.add(jsonEncode({
      'type': 'checkin',
      'payload': checkIn.toJson(),
    }));
  }

  /// Best-effort publish einer transienten Schnellaktion (Pause/Tankstopp/…).
  /// Fire-and-forget wie GPS — eine veraltete Schnellaktion nachzusenden
  /// wäre faktisch falsch, daher bewusst KEINE Offline-Pufferung.
  void publishQuickAction(QuickAction action) {
    final sink = _channel?.sink;
    if (sink == null) return;
    sink.add(jsonEncode({
      'type': 'status',
      'payload': action.toJson(),
    }));
  }

  /// Sendet einen kritischen Frame sofort — oder puffert ihn, solange der
  /// Socket keine Verbindung hat, statt ihn still zu verwerfen. Nur so darf
  /// die UI ehrlich „wird gesendet, sobald online" versprechen.
  void _sendCritical(Map<String, Object?> frame) {
    final encoded = jsonEncode(frame);
    final sink = _channel?.sink;
    if (sink == null) {
      _outboundQueue.enqueue(encoded);
      return;
    }
    sink.add(encoded);
  }

  Future<void> disconnect() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _inboundWatchdog?.cancel();
    _inboundWatchdog = null;
    await _frameSub?.cancel();
    _frameSub = null;
    _setStatus(ConnectionStatus.offline);
    await _channel?.sink.close();
    _channel = null;
    if (!_gpsController.isClosed) await _gpsController.close();
    if (!_statusController.isClosed) await _statusController.close();
    if (!_waypointController.isClosed) await _waypointController.close();
    if (!_hazardController.isClosed) await _hazardController.close();
    if (!_tourController.isClosed) await _tourController.close();
    if (!_checkInController.isClosed) await _checkInController.close();
    if (!_quickActionController.isClosed) {
      await _quickActionController.close();
    }
  }

  void _setStatus(ConnectionStatus next) {
    _currentStatus = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _handleFrame(dynamic frame) {
    // Jeder Inbound-Frame beweist eine lebendige Leitung → Watchdog neu
    // aufziehen (und damit nach dem ERSTEN Frame überhaupt erst scharf).
    _restartInboundWatchdog();
    switch (decodeInboundFrame(frame)) {
      case GpsFrame(:final update):
        _gpsController.add(update);
      case WaypointFrame(:final waypoint):
        _waypointController.add(waypoint);
      case HazardFrame(:final event):
        _hazardController.add(event);
      case TourFrame(:final tour):
        _tourController.add(tour);
      case CheckInFrame(:final checkIn):
        _checkInController.add(checkIn);
      case QuickActionFrame(:final action):
        _quickActionController.add(action);
      case null:
        break;
    }
  }
}
