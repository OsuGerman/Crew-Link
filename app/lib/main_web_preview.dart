import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:async/async.dart' show DelegatingStreamSink;
import 'package:firebase_auth/firebase_auth.dart' show UserCredential;
import 'package:firebase_database/firebase_database.dart' show FirebaseDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app/crew_link_app.dart';
import 'core/models/gps_update.dart';
import 'core/realtime/convoy_socket_client.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/convoy/application/breach_notification_watcher.dart';
import 'features/convoy/application/convoy_providers.dart';
import 'features/onboarding/application/onboarding_profile_notifier.dart';
import 'features/push_to_talk/application/ptt_providers.dart';
import 'features/push_to_talk/data/ptt_channel.dart';
import 'features/push_to_talk/data/ptt_repository.dart';
import 'features/push_to_talk/data/webrtc_ptt_receiver.dart';

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

// ─── Auth-Mock — kein Firebase auf Web ───────────────────────────────────────

class _FakeUserCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// Spielt Apple-Sign-In nach 250 ms erfolgreich vor und signalisiert dem
/// Router via [devSignedInOverrideProvider], dass der Auth-Gate offen ist.
class _DemoAuthRepository implements AuthRepository {
  _DemoAuthRepository(this._markSignedIn);
  final void Function() _markSignedIn;

  @override
  Future<UserCredential> signInWithApple() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _markSignedIn();
    return _FakeUserCredential();
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword(String _, String __) async {
    _markSignedIn();
    return _FakeUserCredential();
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword(
      String _, String __) async {
    _markSignedIn();
    return _FakeUserCredential();
  }

  @override
  Future<void> signOut() async {}
}

/// Stub-FirebaseDatabase — `FirebaseDatabase.instance` würde auf Web ohne
/// Firebase.initializeApp() einen JS-Interop-Crash werfen. Dieser Fake wird
/// `pttReceiverProvider` übergeben und nie wirklich benutzt (Receiver-start
/// ist no-op'd).
class _FakeFirebaseDatabase implements FirebaseDatabase {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// No-Op-Receiver — auf Web gibt es kein WebRTC-Signaling per Firebase.
/// Erbt nur, um die `WebRtcPttReceiver`-Typ-Signatur zu erfüllen.
class _NoopPttReceiver extends WebRtcPttReceiver {
  _NoopPttReceiver(String convoyId)
      : super(
          convoyId: convoyId,
          localUserId: 'preview-local',
          database: _FakeFirebaseDatabase(),
        );

  @override
  Future<void> start() async {}
}

/// In-Memory-Profile-Speicher — umgeht flutter_secure_storage auf Web
/// (kann in Inkognito/locked-down Browsern hängen). Reicht für die Preview,
/// State wird sofort als "completed: true" zurückgegeben nach save().
class _InMemoryOnboardingProfileNotifier extends OnboardingProfileNotifier {
  @override
  Future<OnboardingProfile> build() async =>
      const OnboardingProfile(displayName: '', completed: false);

  @override
  Future<void> save(String displayName) async {
    state = AsyncValue.data(
      OnboardingProfile(displayName: displayName, completed: true),
    );
  }
}

// ─── App-Einstieg ────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase wird auf der Web-Preview komplett übersprungen — RTDB/Auth-
  // Anteile sind via Provider-Overrides bereits durch No-Ops ersetzt
  // (s. breachNotificationWatcherProvider). Der Firebase-JS-SDK init
  // konnte mit Placeholder-Keys den gesamten runApp-Pfad blockieren.

  final backend = _InMemoryBackend();
  final mockHttp = _MockHttpClient(backend);

  runApp(
    _PhoneFrame(
      child: ProviderScope(
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
        // pttReceiverProvider würde sonst FirebaseDatabase.instance lesen
        // und auf Web JS-Interop-crashen sobald ein Convoy aktiv wird.
        pttReceiverProvider.overrideWith(
          (ref, convoyId) => _NoopPttReceiver(convoyId),
        ),
        // Demo-AuthRepository: Apple-Tap → setzt devSignedInOverrideProvider,
        // damit der Router den Auth-Gate als bestanden behandelt (sonst geht
        // der Apple-Button auf Web ins Leere — kein Firebase-Backend).
        authRepositoryProvider.overrideWith(
          (ref) => _DemoAuthRepository(
            () => ref.read(devSignedInOverrideProvider.notifier).state = true,
          ),
        ),
        // In-Memory-Profil-Storage: vermeidet flutter_secure_storage-Hänger.
        onboardingProfileProvider.overrideWith(
          _InMemoryOnboardingProfileNotifier.new,
        ),
        // Local notifications + RTDB breach broadcast brauchen Platform-
        // Channels bzw. funktionierende Firebase-Auth — beides nicht da.
        // Watcher als reine No-Op-Resolution, damit kein Init crasht.
        breachNotificationWatcherProvider.overrideWith((ref) {}),
      ],
      child: const CrewLinkApp(),
      ),
    ),
  );
}

/// Zentriert die App in einer 393-px-breiten Säule (Phone-Breite). Höhe
/// folgt der Browser-Viewport-Höhe, damit nichts off-screen rutscht und
/// der LoginScreen-Spacer-Pattern korrekt bleibt. Außenrum dunkler Filler;
/// der CSS-Bezel-Overlay aus index.html zeichnet den iPhone-Frame.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF0A0A0B),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 393),
          child: child,
        ),
      ),
    );
  }
}
