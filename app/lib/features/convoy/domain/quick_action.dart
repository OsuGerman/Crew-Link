/// One-tap convoy status broadcast — the four actions that cover most convoy
/// chatter (Design "Schnellaktionen"). Transient: shown as a brief banner, not
/// persisted. Wire type `status` (see backend `wire.ts`).
enum QuickActionKind {
  pause,
  fuelStop,
  backInConvoy,
  vehicleProblem;

  String get wireValue => switch (this) {
        QuickActionKind.pause => 'pause',
        QuickActionKind.fuelStop => 'fuel_stop',
        QuickActionKind.backInConvoy => 'back_in_convoy',
        QuickActionKind.vehicleProblem => 'vehicle_problem',
      };

  static QuickActionKind fromWire(String wire) {
    for (final k in QuickActionKind.values) {
      if (k.wireValue == wire) return k;
    }
    return QuickActionKind.pause;
  }
}

class QuickAction {
  const QuickAction({
    required this.memberId,
    required this.kind,
    required this.at,
  });

  factory QuickAction.fromJson(Map<String, Object?> json) => QuickAction(
        memberId: json['memberId']! as String,
        kind: QuickActionKind.fromWire(json['kind']! as String),
        at: DateTime.parse(json['at']! as String),
      );

  final String memberId;
  final QuickActionKind kind;
  final DateTime at;

  Map<String, Object?> toJson() => {
        'memberId': memberId,
        'kind': kind.wireValue,
        'at': at.toUtc().toIso8601String(),
      };
}
