import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:async/async.dart' show DelegatingStreamSink;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app/crew_link_app.dart';
import 'core/firebase/firebase_options.dart';
import 'core/models/gps_update.dart';
import 'core/realtime/convoy_socket_client.dart';
import 'features/convoy/application/breach_notification_watcher.dart';
import 'features/convoy/application/convoy_providers.dart';
import 'features/push_to_talk/application/ptt_providers.dart';
import 'features/push_to_talk/data/ptt_channel.dart';
import 'features/push_to_talk/data/ptt_repository.dart';

// ─── Demo-Daten ──────────────────────────────────────────────────────────────

const _selfMemberId = 'dev-self';
const _selfMemberName = 'You (Preview)';

class _Peer {
  const _Peer(this.id, this.name, this.lat, this.lng);
  final String id;
  final String name;
  final double lat;
  final double lng;
}

const _peers = <_Peer>[
  _Peer('peer-anna', 'Anna · GT3', 48.1380, 11.5762),
  _Peer('peer-ben', 'Ben · M3', 48.1370, 11.5750),
];

// ─── In-Memory-Backend ───────────────────────────────────────────────────────

class _InMemoryBackend {
  final Map<String, Map<String, Object?>> convoysById = {};
  final Map<String, String> inviteToConvoyId = {};
  Map<String, Object?>? vehicle;
  int _counter = 1;

  Map<String, Object?> createConvoy(String name, double proximity) {
    final id = 'cv-${_counter++}';
    final code = _makeInviteCode();
    final members = <Map<String, Object?>>[
      _selfMember(isLeader: true),
      for (final p in _peers)
        {
          'id': p.id,
          'displayName': p.name,
          'vehicleProfileId': null,
          'vehicle': null,
          'isLeader': false,
        },
    ];
    final convoy = <String, Object?>{
      'id': id,
      'name': name,
      'inviteCode': code,
      'proximityWarningMeters': proximity,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'members': members,
    };
    convoysById[id] = convoy;
    inviteToConvoyId[code] = id;
    return convoy;
  }

  Map<String, Object?>? joinConvoy(String inviteCode) {
    final id = inviteToConvoyId[inviteCode.toUpperCase()];
    if (id == null) return null;
    return convoysById[id];
  }

  void leaveConvoy(String convoyId) {
    convoysById.remove(convoyId);
  }

  Map<String, Object?> putVehicle(Map<String, Object?> body) {
    final existing = vehicle;
    final id = existing?['id'] as String? ?? 'veh-${_counter++}';
    final mods = (body['mods'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<String, Object?>>()
        .map((m) => <String, Object?>{
              'id': m['id'] as String? ?? 'mod-${_counter++}',
              'name': m['name'],
              if (m['description'] != null) 'description': m['description'],
              if (m['category'] != null) 'category': m['category'],
            })
        .toList(growable: false);
    vehicle = <String, Object?>{
      'id': id,
      'make': body['make'],
      'model': body['model'],
      if (body['year'] != null) 'year': body['year'],
      if (body['color'] != null) 'color': body['color'],
      'mods': mods,
    };
    return vehicle!;
  }

  void deleteVehicle() => vehicle = null;

  Map<String, Object?> _selfMember({required bool isLeader}) => {
        'id': _selfMemberId,
        'displayName': _selfMemberName,
        'vehicleProfileId': vehicle?['id'],
        'vehicle': vehicle,
        'isLeader': isLeader,
      };

  String _makeInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = math.Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

// ─── Fake http.Client — mockt /convoys, /vehicles/me, /ptt-token ─────────────

class _MockHttpClient extends http.BaseClient {
  _MockHttpClient(this._backend);

  final _InMemoryBackend _backend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final method = request.method;
    final path = request.url.path;
    final raw = request is http.Request ? request.body : '';
    Map<String, Object?>? body;
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) body = decoded.cast<String, Object?>();
      } catch (_) {/* malformed body — let route decide */}
    }

    int status = 200;
    Object? response;

    if (method == 'POST' && path == '/convoys') {
      response = _backend.createConvoy(
        (body?['name'] as String?)?.trim().isNotEmpty == true
            ? body!['name']! as String
            : 'Demo-Konvoi',
        (body?['proximityWarningMeters'] as num?)?.toDouble() ?? 500,
      );
    } else if (method == 'POST' && path == '/convoys/join') {
      final code = (body?['inviteCode'] as String?)?.trim();
      final convoy = code == null ? null : _backend.joinConvoy(code);
      if (convoy == null) {
        status = 404;
        response = {
          'error':
              'Invite-Code unbekannt. Erstelle erst einen Konvoi — der Code wird dir angezeigt.',
        };
      } else {
        response = convoy;
      }
    } else if (method == 'DELETE' && _membershipPath(path) != null) {
      _backend.leaveConvoy(_membershipPath(path)!);
      status = 204;
    } else if (method == 'GET' && path == '/vehicles/me') {
      response = _backend.vehicle;
    } else if (method == 'PUT' && path == '/vehicles/me') {
      response = _backend.putVehicle(body ?? const {});
    } else if (method == 'DELETE' && path == '/vehicles/me') {
      _backend.deleteVehicle();
      status = 204;
    } else if (method == 'POST' && path.endsWith('/ptt-token')) {
      response = {'url': 'wss://preview.local/livekit', 'token': 'preview'};
    } else {
      status = 404;
      response = {'error': 'Preview backend: $method $path nicht gemockt'};
    }

    final bodyBytes = utf8.encode(switch (response) {
      null => 'null',
      _ => jsonEncode(response),
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(bodyBytes),
      status,
      contentLength: bodyBytes.length,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  String? _membershipPath(String path) {
    final m = RegExp(r'^/convoys/([^/]+)/membership$').firstMatch(path);
    return m?.group(1);
  }
}

// ─── Fake WebSocket — simuliert Peers + echot eigene GPS ─────────────────────

class _FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _FakeWebSocketChannel(this.uri) {
    _outboundCtrl.stream.listen(_inbound.add);
    _peerTicker =
        Timer.periodic(const Duration(milliseconds: 1200), _emitPeers);
  }

  final Uri uri;
  final StreamController<dynamic> _inbound =
      StreamController<dynamic>.broadcast();
  final StreamController<dynamic> _outboundCtrl =
      StreamController<dynamic>();
  late final Timer _peerTicker;
  late final _FakeWebSocketSink _sink =
      _FakeWebSocketSink(_outboundCtrl, () async {
    _peerTicker.cancel();
    await _outboundCtrl.close();
    await _inbound.close();
  });
  int _step = 0;

  void _emitPeers(Timer _) {
    _step++;
    for (var i = 0; i < _peers.length; i++) {
      final p = _peers[i];
      final phase = _step + i * 11;
      final lat = p.lat + math.sin(phase / 9.0) * 0.0012;
      final lng = p.lng + math.cos(phase / 9.0) * 0.0012;
      final heading =
          ((math.cos(phase / 9.0) * 90 + 90 + i * 45) % 360 + 360) % 360;
      final frame = jsonEncode({
        'type': 'gps',
        'payload': GpsUpdate(
          memberId: p.id,
          latitude: lat,
          longitude: lng,
          headingDegrees: heading,
          speedMps: 7 + i * 1.5,
          timestamp: DateTime.now(),
        ).toJson(),
      });
      if (!_inbound.isClosed) _inbound.add(frame);
    }
  }

  @override
  Stream<dynamic> get stream => _inbound.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready async {}

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class _FakeWebSocketSink extends DelegatingStreamSink<dynamic>
    implements WebSocketSink {
  _FakeWebSocketSink(StreamController<dynamic> controller, this._onClose)
      : super(controller.sink);

  final Future<void> Function() _onClose;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await super.close();
    await _onClose();
  }
}

// ─── Eigene Position: Slow loop um Marienplatz ───────────────────────────────

Stream<GpsUpdate> _simulatedSelfLocation() async* {
  double lat = 48.1374;
  double lng = 11.5755;
  double heading = 90;
  int step = 0;
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 2));
    step++;
    final phase = step % 40;
    if (phase < 10) {
      lng += 0.00012;
      heading = 90;
    } else if (phase < 20) {
      lat -= 0.00012;
      heading = 180;
    } else if (phase < 30) {
      lng -= 0.00012;
      heading = 270;
    } else {
      lat += 0.00012;
      heading = 0;
    }
    yield GpsUpdate(
      memberId: _selfMemberId,
      latitude: lat,
      longitude: lng,
      headingDegrees: heading,
      speedMps: 8.3,
      timestamp: DateTime.now(),
    );
  }
}

// ─── PTT-No-ops (umgeht native Platform Channels + LiveKit) ──────────────────

class _NoopPttRepository implements PttRepository {
  @override
  Future<void> startTransmitting(String convoyId) =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  @override
  Future<void> stopTransmitting() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  @override
  void sendFrame(Uint8List frame) {}
}

/// Unterdrückt alle MethodChannel-Aufrufe auf Web (kein nativer Handler vorhanden).
class _NoopPttChannel extends PttChannel {
  @override
  Future<void> startRecording() async {}
  @override
  Future<void> stopRecording() async {}
  @override
  Future<void> playFrame(Uint8List frame) async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  Stream<Uint8List> get frames => const Stream.empty();
}

// ─── App-Einstieg ────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase mit den Dummy-Options aus `firebase_options.dart` initialisieren.
  // Reicht für die JS-Interop-Casts in Web-Plugins (RTDB/Auth) — Network-Calls
  // werden später still fehlschlagen, aber die UI rendert nicht mehr rot mit
  // "FirebaseException is not a subtype of JavaScriptObject".
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } catch (_) {
    // Bei einem Re-Init oder fehlender Web-SDK schlucken — Preview muss laufen.
  }

  final backend = _InMemoryBackend();
  final mockHttp = _MockHttpClient(backend);

  runApp(
    ProviderScope(
      overrides: [
        authTokenProvider.overrideWithValue('dev-token'),
        selfMemberIdProvider.overrideWithValue(_selfMemberId),
        httpClientProvider.overrideWithValue(mockHttp),
        pttChannelProvider.overrideWithValue(_NoopPttChannel()),
        convoySocketFactoryProvider.overrideWith((ref) {
          return ({required convoyId, required authToken}) =>
              ConvoySocketClient(
                config: ref.read(apiConfigProvider),
                convoyId: convoyId,
                authToken: authToken,
                channelFactory: _FakeWebSocketChannel.new,
              );
        }),
        selfLocationStreamProvider
            .overrideWith((_) => _simulatedSelfLocation()),
        pttRepositoryProvider.overrideWith((_) => _NoopPttRepository()),
        // Local notifications + RTDB breach broadcast brauchen Platform-
        // Channels bzw. funktionierende Firebase-Auth — beides nicht da.
        // Watcher als reine No-Op-Resolution, damit kein Init crasht.
        breachNotificationWatcherProvider.overrideWith((ref) {}),
      ],
      child: const CrewLinkApp(),
    ),
  );
}
