import 'package:firebase_database/firebase_database.dart';

import '../models/breach_event.dart';

/// Publishes and subscribes to distance-breach events in Firebase RTDB.
///
/// RTDB path: `convoys/{convoyId}/breaches/{pairKey}`
///
/// Debounce: a pair fires at most once per [_debounceWindow] to prevent
/// flooding when members oscillate at the threshold boundary.
///
/// Background push: a Cloud Functions trigger on this path is the planned
/// mechanism for FCM data messages when the app is killed. Client-side FCM
/// bootstrap lives in `main.dart`; the Cloud Function is a follow-up task.
abstract class BreachBroadcastRepository {
  Future<void> publish({
    required String convoyId,
    required String memberAId,
    required String memberBId,
    required double distanceMeters,
    DateTime Function()? clock,
  });

  Stream<BreachEvent> incoming(String convoyId);
}

class RtdbBreachBroadcastRepository implements BreachBroadcastRepository {
  RtdbBreachBroadcastRepository({required FirebaseDatabase db}) : _db = db;

  final FirebaseDatabase _db;

  static const Duration _debounceWindow = Duration(seconds: 60);

  final Map<String, DateTime> _lastPublished = {};

  @override
  Future<void> publish({
    required String convoyId,
    required String memberAId,
    required String memberBId,
    required double distanceMeters,
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)();
    final key = BreachEvent.pairKey(memberAId, memberBId);
    final lastSent = _lastPublished[key];
    if (lastSent != null && now.difference(lastSent) < _debounceWindow) return;
    _lastPublished[key] = now;

    final isAFirst = memberAId.compareTo(memberBId) <= 0;
    final event = BreachEvent(
      id: key,
      convoyId: convoyId,
      memberAId: isAFirst ? memberAId : memberBId,
      memberBId: isAFirst ? memberBId : memberAId,
      distanceMeters: distanceMeters,
      triggeredAt: now,
    );
    await _db.ref('convoys/$convoyId/breaches/$key').set(event.toRtdb());
  }

  @override
  Stream<BreachEvent> incoming(String convoyId) {
    return _db
        .ref('convoys/$convoyId/breaches')
        .onChildAdded
        .map(
          (e) => BreachEvent.fromRtdb(
            e.snapshot.key!,
            convoyId,
            Map<String, Object?>.from(e.snapshot.value! as Map),
          ),
        );
  }
}
