import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

const _kIceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
];

const _kPcConfig = {
  'iceServers': _kIceServers,
  'sdpSemantics': 'unified-plan',
};

/// PTT-Empfangsseite: lauscht auf neue Offers im Konvoi und streamt Opus-Pakete.
///
/// Für jeden aktiven Sender wird eine RTCPeerConnection aufgebaut und
/// SDP-Signaling über Firebase RTDB abgewickelt.
///
/// [frames] liefert rohe Opus-Pakete (20 ms, 48 kHz). Die native Seite
/// (PttAudioChannel.swift) ist für Dekodierung und Wiedergabe zuständig.
class WebRtcPttReceiver {
  WebRtcPttReceiver({
    required String convoyId,
    required String localUserId,
    required FirebaseDatabase database,
  })  : _convoyId = convoyId,
        _localUserId = localUserId,
        _db = database;

  final String _convoyId;
  final String _localUserId;
  final FirebaseDatabase _db;

  final _framesController = StreamController<Uint8List>.broadcast();
  final _peers = <String, RTCPeerConnection>{};
  // All Firebase subscriptions per sender, cancelled in stop().
  final _peerSubs = <String, List<StreamSubscription<dynamic>>>{};
  StreamSubscription<DatabaseEvent>? _offerSub;

  /// Broadcast-Stream empfangener Opus-Pakete (ein Element = 20 ms).
  Stream<Uint8List> get frames => _framesController.stream;

  Future<void> start() async {
    final sessionsRef = _db.ref('ptt_sessions/$_convoyId');
    _offerSub = sessionsRef.onChildAdded.listen((event) {
      final transmitterId = event.snapshot.key;
      if (transmitterId == null || transmitterId == _localUserId) return;

      _peerSubs.putIfAbsent(transmitterId, () => []);
      final offerSub = sessionsRef
          .child('$transmitterId/offer')
          .onValue
          .listen((offerEvent) async {
        final data = offerEvent.snapshot.value as Map<Object?, Object?>?;
        if (data == null || _peers.containsKey(transmitterId)) return;
        await _handleOffer(
          transmitterId: transmitterId,
          sdp: data['sdp'] as String,
          type: data['type'] as String,
          sigRef: sessionsRef.child(transmitterId),
        );
      });
      _peerSubs[transmitterId]!.add(offerSub);
    });
  }

  Future<void> _handleOffer({
    required String transmitterId,
    required String sdp,
    required String type,
    required DatabaseReference sigRef,
  }) async {
    final pc = await createPeerConnection(_kPcConfig);
    _peers[transmitterId] = pc;

    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      // Flat push so sender's onChildAdded on 'answer_ice' receives individual
      // candidate objects directly (not a userId-keyed sub-tree).
      sigRef.child('answer_ice').push().set({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };

    pc.onDataChannel = (dc) {
      dc.onMessage = (msg) {
        if (msg.isBinary && !_framesController.isClosed) {
          _framesController.add(msg.binary);
        }
      };
    };

    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    await sigRef.child('answer').set({
      'sdp': answer.sdp,
      'type': answer.type,
    });

    final iceSub = sigRef.child('ice').onChildAdded.listen((event) async {
      final ice = event.snapshot.value as Map<Object?, Object?>?;
      if (ice == null) return;
      await pc.addCandidate(RTCIceCandidate(
        ice['candidate'] as String?,
        ice['sdpMid'] as String?,
        ice['sdpMLineIndex'] as int?,
      ));
    });
    _peerSubs.putIfAbsent(transmitterId, () => []).add(iceSub);
  }

  Future<void> stop() async {
    await _offerSub?.cancel();
    _offerSub = null;
    for (final subs in _peerSubs.values) {
      for (final sub in subs) {
        await sub.cancel();
      }
    }
    _peerSubs.clear();
    for (final pc in _peers.values) {
      await pc.close();
      await pc.dispose();
    }
    _peers.clear();
    if (!_framesController.isClosed) {
      await _framesController.close();
    }
  }
}
