// Demo entry-point: runs the full UI against in-memory mocks for the
// REST API and the realtime socket. Lets you see the convoy lifecycle,
// live members tile and proximity banner without a backend or DB.
//
// Launch with:
//   flutter run -d chrome -t lib/main_demo.dart
//
// The real entry-point (lib/main.dart) is untouched.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'app/crew_link_app.dart';
import 'core/config/api_config.dart';
import 'core/models/gps_update.dart';
import 'core/realtime/connection_status.dart';
import 'core/realtime/convoy_socket_client.dart';
import 'features/convoy/application/convoy_providers.dart';

const _selfMemberId = 'demo-self';
const _buddyMemberId = 'demo-buddy';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        authTokenProvider.overrideWithValue('demo-token'),
        selfMemberIdProvider.overrideWithValue(_selfMemberId),
        httpClientProvider.overrideWithValue(_buildMockHttpClient()),
        convoySocketFactoryProvider.overrideWithValue(
          ({required convoyId, required authToken}) =>
              _DemoSocketClient(convoyId: convoyId),
        ),
        selfLocationStreamProvider.overrideWith(
          (ref) => const Stream<GpsUpdate>.empty(),
        ),
      ],
      child: const CrewLinkApp(),
    ),
  );
}

http.Client _buildMockHttpClient() {
  final convoys = <String, Map<String, Object?>>{};
  // Pre-seeded vehicle so the editor shows something on first open and
  // the convoy member list matches.
  Map<String, Object?>? myVehicle = <String, Object?>{
    'id': 'demo-vehicle-self',
    'make': 'Tesla',
    'model': 'Model 3 Performance',
    'year': 2024,
    'color': 'Indigoblau',
    'mods': <Map<String, Object?>>[
      {
        'id': 'demo-mod-self-1',
        'name': 'Performance-Wheels 20"',
        'description': null,
        'category': 'wheels',
      },
      {
        'id': 'demo-mod-self-2',
        'name': 'Sport-Spoiler',
        'description': 'Carbon',
        'category': 'exterior',
      },
    ],
  };
  const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const codeLength = 6;
  final rnd = Random();

  String randomCode() {
    return List<String>.generate(
      codeLength,
      (_) => codeAlphabet[rnd.nextInt(codeAlphabet.length)],
    ).join();
  }

  Map<String, Object?> seededConvoy({
    required String name,
    required double thresholdMeters,
  }) {
    final id = 'convoy-${DateTime.now().millisecondsSinceEpoch}';
    final code = randomCode();
    final convoy = <String, Object?>{
      'id': id,
      'name': name,
      'inviteCode': code,
      'members': <Map<String, Object?>>[
        {
          'id': _selfMemberId,
          'displayName': 'Du (Demo)',
          'vehicleProfileId': myVehicle?['id'],
          // Pull the live myVehicle snapshot so editing the profile
          // also reflects in the convoy member list on the next create.
          'vehicle': myVehicle,
          'isLeader': true,
        },
        {
          'id': _buddyMemberId,
          'displayName': 'Demo-Buddy',
          'vehicleProfileId': 'demo-vehicle-buddy',
          'vehicle': {
            'id': 'demo-vehicle-buddy',
            'make': 'BMW',
            'model': 'M2',
            'year': 2023,
            'color': 'Schwarz',
            'mods': <Map<String, Object?>>[
              {
                'id': 'demo-mod-buddy-1',
                'name': 'Track-Brakes',
                'description': null,
                'category': 'wheels',
              },
            ],
          },
          'isLeader': false,
        },
      ],
      'proximityWarningMeters': thresholdMeters,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    convoys[id] = convoy;
    return convoy;
  }

  return MockClient((http.Request req) async {
    final path = req.url.path;
    if (path == '/convoys' && req.method == 'POST') {
      final body = jsonDecode(req.body) as Map<String, Object?>;
      final convoy = seededConvoy(
        name: body['name']! as String,
        thresholdMeters:
            (body['proximityWarningMeters'] as num?)?.toDouble() ?? 500,
      );
      return http.Response(jsonEncode(convoy), 201);
    }
    if (path == '/convoys/join' && req.method == 'POST') {
      final body = jsonDecode(req.body) as Map<String, Object?>;
      final code = body['inviteCode'] as String?;
      Map<String, Object?>? found;
      for (final c in convoys.values) {
        if (c['inviteCode'] == code) {
          found = c;
          break;
        }
      }
      if (found == null) {
        // Pretend the code maps to a fresh demo convoy so users can
        // explore the joined-state flow without first creating one.
        final convoy = seededConvoy(name: 'Geteilter Konvoi', thresholdMeters: 500);
        // Replace generated code with the user-typed code for realism.
        convoy['inviteCode'] = code;
        return http.Response(jsonEncode(convoy), 200);
      }
      return http.Response(jsonEncode(found), 200);
    }
    if (path.startsWith('/convoys/') &&
        path.endsWith('/membership') &&
        req.method == 'DELETE') {
      return http.Response('', 204);
    }
    if (path == '/vehicles/me' && req.method == 'GET') {
      return http.Response(
        myVehicle == null ? 'null' : jsonEncode(myVehicle),
        200,
      );
    }
    if (path == '/vehicles/me' && req.method == 'PUT') {
      final body = jsonDecode(req.body) as Map<String, Object?>;
      final incomingMods =
          (body['mods'] as List<Object?>?) ?? const <Object?>[];
      final now = DateTime.now().microsecondsSinceEpoch;
      final assignedMods = <Map<String, Object?>>[];
      for (var i = 0; i < incomingMods.length; i++) {
        final m = (incomingMods[i]! as Map).cast<String, Object?>();
        assignedMods.add(<String, Object?>{
          'id': 'demo-mod-$now-$i',
          'name': m['name'],
          'description': m['description'],
          'category': m['category'],
        });
      }
      final updated = <String, Object?>{
        'id': myVehicle?['id'] ??
            'demo-vehicle-${DateTime.now().millisecondsSinceEpoch}',
        'make': body['make'],
        'model': body['model'],
        'year': body['year'],
        'color': body['color'],
        'mods': assignedMods,
      };
      myVehicle = updated;
      return http.Response(jsonEncode(updated), 200);
    }
    if (path == '/vehicles/me' && req.method == 'DELETE') {
      myVehicle = null;
      return http.Response('', 204);
    }
    return http.Response('not found', 404);
  });
}

class _DemoSocketClient extends ConvoySocketClient {
  _DemoSocketClient({required super.convoyId})
      : super(
          config: ApiConfig.local(),
          authToken: 'demo-token',
        );

  final StreamController<GpsUpdate> _outbound =
      StreamController<GpsUpdate>.broadcast();

  Timer? _selfTimer;
  Timer? _buddyTimer;

  static const double _baseLat = 52.5200;
  static const double _baseLon = 13.4050;
  static const double _selfStepLon = 0.00005; // ~3 m east per tick
  static const double _buddyStartOffset = 0.00045; // ~30 m east of self
  static const double _buddyDriftStep = 0.00010; // peels away over time
  static const double _initialHeading = 90;
  static const double _selfSpeed = 6;
  static const double _buddySpeed = 6.5;

  double _selfLon = _baseLon;
  double _buddyOffset = _buddyStartOffset;

  @override
  Stream<GpsUpdate> get gpsUpdates => _outbound.stream;

  // Demo socket is in-memory: it is always "connected" from the UI's
  // perspective. Override the status surface to skip the connecting
  // banner that would otherwise show forever.
  @override
  ConnectionStatus get currentStatus => ConnectionStatus.connected;

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      Stream<ConnectionStatus>.value(ConnectionStatus.connected);

  @override
  Future<void> connect() async {
    _emitSelf();
    _emitBuddy();
    _selfTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _selfLon += _selfStepLon;
      _emitSelf();
    });
    _buddyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _buddyOffset += _buddyDriftStep;
      _emitBuddy();
    });
  }

  void _emitSelf() {
    _emit(_selfMemberId, _baseLat, _selfLon, _selfSpeed);
  }

  void _emitBuddy() {
    _emit(_buddyMemberId, _baseLat, _selfLon + _buddyOffset, _buddySpeed);
  }

  void _emit(String memberId, double lat, double lon, double speed) {
    if (_outbound.isClosed) {
      return;
    }
    _outbound.add(GpsUpdate(
      memberId: memberId,
      latitude: lat,
      longitude: lon,
      headingDegrees: _initialHeading,
      speedMps: speed,
      timestamp: DateTime.now().toUtc(),
    ));
  }

  @override
  void publishLocation(GpsUpdate update) {
    // No-op: the periodic emitters above already feed the local stream.
  }

  @override
  Future<void> disconnect() async {
    _selfTimer?.cancel();
    _buddyTimer?.cancel();
    _selfTimer = null;
    _buddyTimer = null;
    if (!_outbound.isClosed) {
      await _outbound.close();
    }
  }
}
