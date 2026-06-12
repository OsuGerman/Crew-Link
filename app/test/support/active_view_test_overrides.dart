import 'dart:async';
import 'dart:typed_data';

import 'package:crew_link/core/carplay/carplay_providers.dart';
import 'package:crew_link/core/models/gps_update.dart';
import 'package:crew_link/features/convoy/application/breach_notification_watcher.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/application/convoy_split_watcher.dart';
import 'package:crew_link/features/convoy/application/lost_connection_watcher.dart';
import 'package:crew_link/features/convoy/application/wakelock_provider.dart';
import 'package:crew_link/features/push_to_talk/application/ptt_providers.dart';
import 'package:crew_link/features/push_to_talk/data/webrtc_ptt_receiver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No-op receiver so pttReceiverProvider can be overridden without touching
/// FirebaseDatabase.instance (which throws "No Firebase App" in widget tests).
class _NoopPttReceiver implements WebRtcPttReceiver {
  @override
  Stream<Uint8List> get frames => const Stream<Uint8List>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

/// No-op wakelock so convoyWakelockProvider never reaches the wakelock_plus
/// platform channel (MissingPluginException) in widget tests.
class NoopWakelockControl implements WakelockControl {
  const NoopWakelockControl();

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

/// Stubs the side-effect provider wiring that [ActiveConvoyView] eagerly
/// `ref.watch`es on build — Firebase FCM (breach/split/lost-connection
/// watchers), WebRTC/Firebase-Database PTT (receiver/playback/frame-routing)
/// and the CarPlay method channel. Without these stubs the active view's build
/// throws (FirebaseException / MissingPluginException) in a widget test that
/// has no platform or initialised Firebase.
List<Override> activeViewStubOverrides() => <Override>[
      breachNotificationWatcherProvider.overrideWith((ref) {}),
      convoySplitWatcherProvider.overrideWith((ref) {}),
      lostConnectionWatcherProvider.overrideWith((ref) {}),
      carPlayConvoyStateWiringProvider.overrideWith((ref) {}),
      pttFrameRoutingProvider.overrideWith((ref, convoyId) {}),
      pttPlaybackProvider.overrideWith((ref, convoyId) {}),
      pttReceiverProvider.overrideWith((ref, convoyId) => _NoopPttReceiver()),
      wakelockControlProvider.overrideWithValue(const NoopWakelockControl()),
      // The convoy session now folds in the device's own GPS; stub it so tests
      // don't reach the geolocator plugin (unavailable in widget tests).
      selfLocationStreamProvider.overrideWith(
        (ref) => const Stream<GpsUpdate>.empty(),
      ),
    ];
