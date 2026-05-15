import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/convoy.dart';
import '../../../core/notifications/breach_broadcast_repository.dart';
import '../../../core/notifications/notification_service.dart';
import '../domain/proximity_warning.dart';
import 'convoy_providers.dart';

// Notification IDs are 32-bit integers; cap the modulus to stay in range.
const int _notifIdMod = 100000;

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = LocalNotificationService();
  // Platform channels must be initialised before the first show() call.
  // The first breach takes several seconds, so init() will be ready in time.
  unawaited(service.init());
  return service;
});

final breachBroadcastRepositoryProvider =
    Provider<BreachBroadcastRepository>((ref) {
  return RtdbBreachBroadcastRepository(
    db: ref.watch(realtimeDatabaseProvider),
  );
});

/// Coordinates breach notifications for the active convoy:
///
/// 1. **Local detection → self notification + RTDB broadcast**
///    When [proximityWarningsProvider] fires, a local notification is shown
///    immediately and the breach is written to RTDB so all other members see it.
///
/// 2. **RTDB broadcast → other-member notifications**
///    Breaches between third parties (neither member is self) are received from
///    RTDB and shown as a local notification on every convoy member's device.
///
/// Activate by watching this provider in the active-convoy widget tree.
final breachNotificationWatcherProvider = Provider.autoDispose<void>((ref) {
  final service = ref.read(notificationServiceProvider);
  final repo = ref.read(breachBroadcastRepositoryProvider);
  final selfId = ref.watch(selfMemberIdProvider);
  final convoy = ref.watch(currentConvoyProvider);

  // — Local detections -------------------------------------------------------
  ref.listen<AsyncValue<ProximityWarning>>(
    proximityWarningsProvider,
    (_, next) {
      next.whenData((warning) {
        final distStr = warning.distanceMeters.toStringAsFixed(0);
        final peerName = _displayName(convoy, warning.otherMemberId);
        final id = warning.otherMemberId.hashCode.abs() % _notifIdMod;
        unawaited(service.show(
          id: id,
          title: 'Konvoi-Warnung',
          body: '$peerName ist $distStr m entfernt!',
        ));
        if (convoy != null) {
          unawaited(repo.publish(
            convoyId: convoy.id,
            memberAId: selfId,
            memberBId: warning.otherMemberId,
            distanceMeters: warning.distanceMeters,
          ));
        }
      });
    },
  );

  // — Incoming RTDB breaches between other members ---------------------------
  if (convoy != null) {
    final sub = repo.incoming(convoy.id).listen((event) {
      // Skip: self is already notified above via the local ProximityWarning.
      if (event.memberAId == selfId || event.memberBId == selfId) return;
      final nameA = _displayName(convoy, event.memberAId);
      final nameB = _displayName(convoy, event.memberBId);
      final distStr = event.distanceMeters.toStringAsFixed(0);
      final id = event.id.hashCode.abs() % _notifIdMod;
      unawaited(service.show(
        id: id,
        title: 'Konvoi-Warnung',
        body: '$nameA und $nameB sind $distStr m auseinander!',
      ));
    });
    ref.onDispose(() => unawaited(sub.cancel()));
  }
});

String _displayName(Convoy? convoy, String memberId) {
  if (convoy == null) return memberId;
  return convoy.members
          .where((m) => m.id == memberId)
          .firstOrNull
          ?.displayName ??
      memberId;
}
