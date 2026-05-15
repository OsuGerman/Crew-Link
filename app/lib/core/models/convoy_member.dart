import 'vehicle_profile.dart';

class ConvoyMember {
  const ConvoyMember({
    required this.id,
    required this.displayName,
    this.vehicleProfileId,
    this.vehicle,
    this.isLeader = false,
  });

  factory ConvoyMember.fromJson(Map<String, Object?> json) {
    final rawVehicle = json['vehicle'];
    return ConvoyMember(
      id: json['id']! as String,
      displayName: json['displayName']! as String,
      vehicleProfileId: json['vehicleProfileId'] as String?,
      vehicle: rawVehicle is Map
          ? VehicleProfile.fromJson(rawVehicle.cast<String, Object?>())
          : null,
      isLeader: (json['isLeader'] as bool?) ?? false,
    );
  }

  final String id;
  final String displayName;
  final String? vehicleProfileId;
  final VehicleProfile? vehicle;
  final bool isLeader;

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'vehicleProfileId': vehicleProfileId,
        'vehicle': vehicle?.toJson(),
        'isLeader': isLeader,
      };

  ConvoyMember copyWith({
    String? displayName,
    String? vehicleProfileId,
    VehicleProfile? vehicle,
    bool? isLeader,
  }) {
    return ConvoyMember(
      id: id,
      displayName: displayName ?? this.displayName,
      vehicleProfileId: vehicleProfileId ?? this.vehicleProfileId,
      vehicle: vehicle ?? this.vehicle,
      isLeader: isLeader ?? this.isLeader,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConvoyMember &&
          other.id == id &&
          other.displayName == displayName &&
          other.vehicleProfileId == vehicleProfileId &&
          other.vehicle == vehicle &&
          other.isLeader == isLeader;

  @override
  int get hashCode =>
      Object.hash(id, displayName, vehicleProfileId, vehicle, isLeader);
}
