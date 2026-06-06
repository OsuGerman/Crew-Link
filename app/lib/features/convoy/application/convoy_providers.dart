import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/models/convoy.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/realtime/connection_status.dart';
import '../../../core/realtime/convoy_socket_client.dart';
import '../data/adaptive_interval.dart';
import '../data/convoy_api.dart';
import '../data/gps_producer.dart';
import '../data/gps_producer_lifecycle_observer.dart';
import '../data/location_publisher.dart';
import '../domain/convoy_session.dart';
import '../domain/proximity_warning.dart';

final apiConfigProvider = Provider<ApiConfig>((ref) {
  return ApiConfig.fromEnvironment();
});

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final convoyApiProvider = Provider<ConvoyApi>((ref) {
  return ConvoyApi(
    config: ref.watch(apiConfigProvider),
    client: ref.watch(httpClientProvider),
  );
});

/// Bearer token for the current authenticated user. Real auth is a
/// later milestone — the provider is overridable in tests / DI.
final authTokenProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'authTokenProvider must be overridden before use (auth not wired yet).',
  );
});

/// Identifier of the local user inside any joined convoy. Overridable
/// from tests; real auth will provide this from the token claims.
final selfMemberIdProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'selfMemberIdProvider must be overridden before use.',
  );
});

/// Wall-clock source used by time-sensitive logic (e.g. the proximity
/// stale-position filter). Overridable so widget/unit tests can pin time
/// without monkey-patching DateTime.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The convoy the user is currently in (or `null` before create/join).
/// Mutated by the create/join flows; the active session can later derive
/// its socket connection from this.
final currentConvoyProvider = StateProvider<Convoy?>((ref) => null);

/// While a convoy is active, periodically re-fetches its roster over REST so a
/// member who joins after you appears without waiting for their first GPS frame
/// (there is no membership push yet). Watched by the active convoy view; the
/// timer auto-cancels when it unmounts. Updates [currentConvoyProvider] only
/// when the member set actually changed (avoids needless rebuilds).
final convoyRosterRefreshProvider = Provider.autoDispose<void>((ref) {
  final convoyId = ref.watch(currentConvoyProvider.select((c) => c?.id));
  if (convoyId == null) return;
  final timer = Timer.periodic(const Duration(seconds: 12), (_) async {
    try {
      final fresh = await ref.read(convoyApiProvider).getConvoy(
            convoyId: convoyId,
            authToken: ref.read(authTokenProvider),
          );
      final current = ref.read(currentConvoyProvider);
      if (current == null || current.id != convoyId) return;
      final currentIds = current.members.map((m) => m.id).toSet();
      final freshIds = fresh.members.map((m) => m.id).toSet();
      if (currentIds.length != freshIds.length ||
          !currentIds.containsAll(freshIds)) {
        ref.read(currentConvoyProvider.notifier).state = fresh;
      }
    } catch (_) {
      // Transient (offline / backend cold start) — retry on the next tick.
    }
  });
  ref.onDispose(timer.cancel);
});

/// Factory that constructs a real-time socket client for a convoy. Kept
/// as a factory (not a direct provider) so test/CI can swap the socket
/// implementation without touching every consumer.
typedef ConvoySocketFactory = ConvoySocketClient Function({
  required String convoyId,
  required String authToken,
});

final convoySocketFactoryProvider = Provider<ConvoySocketFactory>((ref) {
  final config = ref.watch(apiConfigProvider);
  return ({required convoyId, required authToken}) => ConvoySocketClient(
        config: config,
        convoyId: convoyId,
        authToken: authToken,
      );
});

/// Live socket client for the currently joined convoy. `null` while in
/// the lobby. Auto-disposed when the convoy changes or the listener tree
/// goes away.
final convoySocketProvider =
    Provider.autoDispose<ConvoySocketClient?>((ref) {
  final convoy = ref.watch(currentConvoyProvider);
  if (convoy == null) {
    return null;
  }
  final factory = ref.watch(convoySocketFactoryProvider);
  final token = ref.watch(authTokenProvider);
  final client = factory(convoyId: convoy.id, authToken: token);
  unawaited(client.connect());
  ref.onDispose(() {
    unawaited(client.disconnect());
  });
  return client;
});

/// Lazily merges two GPS streams into one and cancels both sources when the
/// listener cancels — folds the device's own position into the convoy session
/// alongside the WebSocket feed without leaking subscriptions.
Stream<GpsUpdate> _mergeGps(Stream<GpsUpdate> a, Stream<GpsUpdate> b) {
  late final StreamController<GpsUpdate> controller;
  StreamSubscription<GpsUpdate>? subA;
  StreamSubscription<GpsUpdate>? subB;
  controller = StreamController<GpsUpdate>(
    onListen: () {
      subA = a.listen(controller.add, onError: controller.addError);
      subB = b.listen(controller.add, onError: controller.addError);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
      await controller.close();
    },
  );
  return controller.stream;
}

/// Live convoy session derived from the socket client and the local
/// member id. `null` while in the lobby. Started eagerly so the
/// proximity warning service begins evaluating as soon as updates flow.
final convoySessionProvider =
    Provider.autoDispose<ConvoySession?>((ref) {
  final convoy = ref.watch(currentConvoyProvider);
  final socket = ref.watch(convoySocketProvider);
  if (convoy == null || socket == null) {
    return null;
  }
  final session = ConvoySession(
    selfMemberId: ref.watch(selfMemberIdProvider),
    // Fold the device's own GPS in locally: the backend fan-out never echoes
    // the sender's own frames, so without this the user never appears on their
    // own map and proximity has no self-position to measure against.
    incoming: _mergeGps(
      socket.gpsUpdates,
      ref.watch(selfLocationStreamProvider),
    ),
    thresholdMeters: convoy.proximityWarningMeters,
    clock: ref.watch(clockProvider),
  )..start();
  ref.onDispose(session.dispose);
  return session;
});

/// Stream of live GPS updates from the active session, or an empty
/// stream when there is no active convoy. Consumers in the UI tree can
/// watch this without caring whether a session exists yet.
final liveGpsUpdatesProvider =
    StreamProvider.autoDispose<GpsUpdate>((ref) {
  final session = ref.watch(convoySessionProvider);
  if (session == null) {
    return const Stream<GpsUpdate>.empty();
  }
  return session.gpsUpdates;
});

/// Stream of proximity warnings from the active session.
final proximityWarningsProvider =
    StreamProvider.autoDispose<ProximityWarning>((ref) {
  final session = ref.watch(convoySessionProvider);
  if (session == null) {
    return const Stream<ProximityWarning>.empty();
  }
  return session.warnings;
});

/// Latest GPS position per member in the active convoy. Empty map while
/// in the lobby. Feeds the live member list and (later) the live map.
final livePositionsProvider =
    StreamProvider.autoDispose<Map<String, GpsUpdate>>((ref) {
  final session = ref.watch(convoySessionProvider);
  if (session == null) {
    return Stream<Map<String, GpsUpdate>>.value(const {});
  }
  return session.positions.map(
    (snapshot) => Map<String, GpsUpdate>.unmodifiable(snapshot),
  );
});

/// Live connection status of the active convoy socket. Empty stream
/// (loading) when no convoy is active. The provider seeds the stream
/// with the socket's current status on subscribe so the UI doesn't
/// flicker through a "loading" state for an already-connected socket.
final convoySocketStatusProvider =
    StreamProvider.autoDispose<ConnectionStatus>((ref) {
  final socket = ref.watch(convoySocketProvider);
  if (socket == null) {
    return const Stream<ConnectionStatus>.empty();
  }
  final controller = StreamController<ConnectionStatus>();
  controller.add(socket.currentStatus);
  final sub = socket.connectionStatus.listen(controller.add);
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});

/// Managed GPS producer for the local device. Auto-disposed when the
/// provider scope goes away; starts immediately with slow bucket (5 s)
/// and accelerates once speed data arrives.
///
/// Wires two throttle overrides automatically:
/// - [GpsProducerLifecycleObserver]: forces slow bucket while app is backgrounded.
/// - Battery watcher: forces slow bucket when device battery < 20 %.
final gpsProducerProvider = Provider.autoDispose<GpsProducer>((ref) {
  final producer =
      GpsProducer(memberId: ref.watch(selfMemberIdProvider))..start();
  final lifecycleObserver = GpsProducerLifecycleObserver(producer);

  // Battery-level adaptation — unavailable on web/desktop stubs, so wrapped
  // in try/catch; GPS falls back to speed-only adaptive sampling on failure.
  StreamSubscription<BatteryState>? batterySub;
  if (!kIsWeb) {
    final battery = Battery();
    Future<void> applyLevel() async {
      try {
        final level = await battery.batteryLevel;
        producer.lowBattery = level < 20;
      } catch (_) {}
    }
    unawaited(applyLevel());
    batterySub =
        battery.onBatteryStateChanged.listen((_) => unawaited(applyLevel()));
  }

  ref.onDispose(() {
    lifecycleObserver.dispose();
    unawaited(batterySub?.cancel());
    unawaited(producer.dispose());
  });
  return producer;
});

/// Source of device-side GPS updates tagged for the local member.
/// Backed by [gpsProducerProvider]; overridable in tests for synthetic streams.
final selfLocationStreamProvider = Provider.autoDispose<Stream<GpsUpdate>>((ref) {
  // Broadcast: consumed by both the publisher (→ WS) and the convoy session
  // (→ live map + proximity) now that the device's own position is folded in.
  return ref.watch(gpsProducerProvider).stream.asBroadcastStream();
});

/// Publishes the local member's GPS updates to the convoy socket while
/// the user is in a convoy. Auto-disposed on leave; throttled to 1 Hz to
/// respect battery + bandwidth budget (rule: GPS updates exclusively via
/// WebSocket, never polling).
final locationPublisherProvider =
    Provider.autoDispose<LocationPublisher?>((ref) {
  final socket = ref.watch(convoySocketProvider);
  if (socket == null) {
    return null;
  }
  final publisher = LocationPublisher(
    source: ref.watch(selfLocationStreamProvider),
    sink: socket.publishLocation,
    // Drive the throttle from actual motion — parked phone uploads
    // every 5 s, highway every 1 s. Directly addresses the
    // "<8 % Akku pro Stunde" goal.
    intervalStrategy: adaptiveGpsInterval,
  )..start();
  ref.onDispose(() {
    unawaited(publisher.dispose());
  });
  return publisher;
});

