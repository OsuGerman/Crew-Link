/// Status einer aktiven Push-to-Talk-Session.
enum PttSessionState { idle, transmitting, receiving }

class PttSession {
  const PttSession({required this.state, required this.speakerMemberId});

  final PttSessionState state;
  final String? speakerMemberId;
}
