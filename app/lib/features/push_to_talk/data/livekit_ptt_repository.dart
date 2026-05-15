import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

import 'ptt_repository.dart';

class LiveKitPttRepository implements PttRepository {
  LiveKitPttRepository({
    required this.authToken,
    required this.backendBaseUrl,
  });

  final String authToken;
  final String backendBaseUrl;

  Room? _room;

  @override
  Future<void> startTransmitting(String convoyId) async {
    final uri = Uri.parse('$backendBaseUrl/convoys/$convoyId/ptt-token');
    final response = await http.post(
      uri,
      headers: {'Authorization': 'Bearer $authToken'},
    );
    if (response.statusCode != 200) {
      throw Exception('PTT token fetch failed: HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final livekitUrl = json['url'] as String;
    final token = json['token'] as String;

    final room = Room();
    await room.connect(livekitUrl, token);
    await room.localParticipant?.setMicrophoneEnabled(true);
    _room = room;
  }

  @override
  Future<void> stopTransmitting() async {
    await _room?.localParticipant?.setMicrophoneEnabled(false);
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
  }

  /// LiveKit verwaltet Audio-Encoding intern — sendFrame ist für SFU-Pfad kein op.
  @override
  void sendFrame(Uint8List frame) {}
}
