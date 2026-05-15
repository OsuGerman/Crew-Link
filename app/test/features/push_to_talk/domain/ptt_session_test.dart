import 'package:crew_link/features/push_to_talk/domain/ptt_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PttSession', () {
    test('idle session has no speaker', () {
      const session = PttSession(
        state: PttSessionState.idle,
        speakerMemberId: null,
      );
      expect(session.state, PttSessionState.idle);
      expect(session.speakerMemberId, isNull);
    });

    test('transmitting session carries speakerId', () {
      const session = PttSession(
        state: PttSessionState.transmitting,
        speakerMemberId: 'member-42',
      );
      expect(session.state, PttSessionState.transmitting);
      expect(session.speakerMemberId, 'member-42');
    });
  });
}
