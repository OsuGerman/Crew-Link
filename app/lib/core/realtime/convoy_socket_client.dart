import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import '../models/gps_update.dart';
import 'connection_status.dart';

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
/// Reconnect attempts continue until `disconnect()` is called.
class ConvoySocketClient {
  ConvoySocketClient({
    required this.config,
    required this.convoyId,
    required this.authToken,
    WebSocketChannelFactory? channelFactory,
    Duration baseRetryDelay = const Duration(seconds: 1),
    Duration maxRetryDelay = const Duration(seconds: 30),
    math.Random? random,
  })  : _channelFactory =
            channelFactory ?? ((uri) => WebSocketChannel.connect(uri)),
        _baseRetryDelay = baseRetryDelay,
        _maxRetryDelay = maxRetryDelay,
        _random = random ?? math.Random();

  final ApiConfig config;
  final String convoyId;
  final String authToken;

  final WebSocketChannelFactory _channelFactory;
  final Duration _baseRetryDelay;
  final Duration _maxRetryDelay;
  final math.Random _random;

  static const int _backoffExponentCap = 5;
  static const double _jitterFraction = 0.25;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _frameSub;
  Timer? _reconnectTimer;
  int _retryAttempt = 0;
  bool _disposed = false;
  ConnectionStatus _currentStatus = ConnectionStatus.connecting;

  final StreamController<GpsUpdate> _gpsController =
      StreamController<GpsUpdate>.broadcast();
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();

  Stream<GpsUpdate> get gpsUpdates => _gpsController.stream;
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;
  ConnectionStatus get currentStatus => _currentStatus;

  Future<void> connect() async {
    _disposed = false;
    await _attemptConnect();
  }

  Future<void> _attemptConnect() async {
    if (_disposed) return;
    _setStatus(ConnectionStatus.connecting);
    final endpoint = config.wsBaseUrl.replace(
      path: '/convoys/$convoyId/stream',
      queryParameters: {'token': authToken},
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
    } catch (_) {
      _onChannelLost();
    }
  }

  void _onChannelLost() {
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

  /// Best-effort publish. Silently drops the frame when the socket is
  /// not currently connected (handshake in progress, tunnel, etc.) —
  /// GPS is a fire-and-forget firehose where the next 1 Hz tick will
  /// carry a fresher position anyway. PTT and other lossy-critical
  /// payloads must NOT reuse this code path: they need explicit
  /// buffering + flush-on-reconnect semantics.
  void publishLocation(GpsUpdate update) {
    final sink = _channel?.sink;
    if (sink == null) return;
    sink.add(jsonEncode({'type': 'gps', 'payload': update.toJson()}));
  }

  Future<void> disconnect() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _frameSub?.cancel();
    _frameSub = null;
    _setStatus(ConnectionStatus.offline);
    await _channel?.sink.close();
    _channel = null;
    if (!_gpsController.isClosed) await _gpsController.close();
    if (!_statusController.isClosed) await _statusController.close();
  }

  void _setStatus(ConnectionStatus next) {
    _currentStatus = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _handleFrame(dynamic frame) {
    if (frame is! String) return;
    final decoded = jsonDecode(frame);
    if (decoded is! Map) return;
    final type = decoded['type'];
    if (type == 'gps') {
      final payload = (decoded['payload']! as Map).cast<String, Object?>();
      _gpsController.add(GpsUpdate.fromJson(payload));
    }
  }
}
