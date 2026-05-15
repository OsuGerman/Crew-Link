import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'ptt_repository.dart';

const _kIceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
];

const _kPcConfig = {
  'iceServers': _kIceServers,
  'sdpSemantics': 'unified-plan',
};

/// PTT-Sendeside: WebRTC DataChannel + Opus (20 ms Pakete, unordered/unreliable).
///
/// Audio-Capture liegt beim Aufrufer (PttStateNotifier → PttChannel).
/// Frames werden per [sendFrame] durchgereicht, sobald der DataChannel offen ist.
///
/// Signaling über Firebase RTDB: /ptt_sessions/{convoyId}/{userId}
/// Produktions-Hinweis: für N>4 Teilnehmer SFU (LiveKit) bevorzugen.
class WebRtcDataChannelPttRepository implements PttRepository {
  WebRtcDataChannelPttRepository({
    required String userId,
    required FirebaseDatabase database,
  })  : _userId = userId,
        _db = database;

  final String _userId;
  final FirebaseDatabase _db;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;

  @override
  Future<void> startTransmitting(String convoyId) async {
    final sigRef = _db.ref('ptt_sessions/$convoyId/$_userId');

    _pc = await createPeerConnection(_kPcConfig);

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      sigRef.child('ice').push().set({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // ordered=false + maxRetransmits=0: Latenz vor Zuverlässigkeit
    final dcInit = RTCDataChannelInit()
      ..ordered = false
      ..maxRetransmits = 0;
    _dc = await _pc!.createDataChannel('opus-ptt', dcInit);

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await sigRef.child('offer').set({
      'sdp': offer.sdp,
      'type': offer.type,
    });

    sigRef.child('answer').onValue.listen((event) async {
      final data = event.snapshot.value as Map<Object?, Object?>?;
      if (data == null || _pc == null) return;
      final sdp = data['sdp'] as String?;
      final type = data['type'] as String?;
      if (sdp == null || type == null) return;
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
    });

    sigRef.child('answer_ice').onChildAdded.listen((event) async {
      final ice = event.snapshot.value as Map<Object?, Object?>?;
      if (ice == null || _pc == null) return;
      await _pc!.addCandidate(RTCIceCandidate(
        ice['candidate'] as String?,
        ice['sdpMid'] as String?,
        ice['sdpMLineIndex'] as int?,
      ));
    });
  }

  /// Sendet ein Opus-Paket durch den offenen DataChannel.
  /// Pakete die vor Channel-Open ankommen werden verworfen (PTT-akzeptabel).
  @override
  void sendFrame(Uint8List frame) {
    if (_dc?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dc!.send(RTCDataChannelMessage.fromBinary(frame));
    }
  }

  @override
  Future<void> stopTransmitting() async {
    await _dc?.close();
    _dc = null;
    await _pc?.close();
    await _pc?.dispose();
    _pc = null;
  }
}
