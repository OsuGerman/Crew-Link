import 'convoy_member.dart';

class Convoy {
  const Convoy({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.members,
    required this.proximityWarningMeters,
    required this.createdAt,
  });

  factory Convoy.fromJson(Map<String, Object?> json) {
    final rawMembers = (json['members'] as List<Object?>? ?? const <Object?>[]);
    return Convoy(
      id: json['id']! as String,
      name: json['name']! as String,
      inviteCode: json['inviteCode']! as String,
      members: rawMembers
          .map((m) => ConvoyMember.fromJson(
                (m! as Map).cast<String, Object?>(),
              ))
          .toList(growable: false),
      proximityWarningMeters:
          (json['proximityWarningMeters'] as num?)?.toDouble() ?? 500,
      createdAt: DateTime.parse(json['createdAt']! as String),
    );
  }

  final String id;
  final String name;
  final String inviteCode;
  final List<ConvoyMember> members;
  final double proximityWarningMeters;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'inviteCode': inviteCode,
        'members': members.map((m) => m.toJson()).toList(growable: false),
        'proximityWarningMeters': proximityWarningMeters,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}
