import 'vehicle_mod.dart';

/// Snapshot of a user's vehicle profile. `mods` is always non-null;
/// defaults to empty for older API responses that don't include the field.
class VehicleProfile {
  const VehicleProfile({
    required this.id,
    required this.make,
    required this.model,
    this.year,
    this.color,
    this.mods = const <VehicleMod>[],
    this.powerKw,
    this.drivetrain,
    this.displacement,
    this.transmissionType,
  });

  factory VehicleProfile.fromJson(Map<String, Object?> json) {
    final rawMods = json['mods'] as List<Object?>?;
    return VehicleProfile(
      id: json['id']! as String,
      make: json['make']! as String,
      model: json['model']! as String,
      year: (json['year'] as num?)?.toInt(),
      color: json['color'] as String?,
      mods: rawMods == null
          ? const <VehicleMod>[]
          : rawMods
              .map((e) => VehicleMod.fromJson(
                    (e! as Map).cast<String, Object?>(),
                  ))
              .toList(growable: false),
      powerKw: (json['power_kw'] as num?)?.toInt(),
      drivetrain: json['drivetrain'] as String?,
      displacement: (json['displacement'] as num?)?.toInt(),
      transmissionType: json['transmission_type'] as String?,
    );
  }

  final String id;
  final String make;
  final String model;
  final int? year;
  final String? color;
  final List<VehicleMod> mods;

  /// Engine output in kilowatts.
  final int? powerKw;

  /// Drivetrain layout: 'FWD' | 'RWD' | 'AWD' | '4WD'.
  final String? drivetrain;

  /// Engine displacement in cubic centimetres (e.g. 3000 for 3.0 L).
  final int? displacement;

  /// Gearbox type: 'manual' | 'automatic' | 'dct' | 'cvt' | 'electric'.
  final String? transmissionType;

  String get headline {
    if (year == null) return '$make $model';
    return '$make $model · $year';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'make': make,
        'model': model,
        'year': year,
        'color': color,
        'mods': mods.map((m) => m.toJson()).toList(growable: false),
        'power_kw': powerKw,
        'drivetrain': drivetrain,
        'displacement': displacement,
        'transmission_type': transmissionType,
      };

  VehicleProfile copyWith({
    String? make,
    String? model,
    int? year,
    String? color,
    List<VehicleMod>? mods,
    int? powerKw,
    String? drivetrain,
    int? displacement,
    String? transmissionType,
  }) {
    return VehicleProfile(
      id: id,
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      color: color ?? this.color,
      mods: mods ?? this.mods,
      powerKw: powerKw ?? this.powerKw,
      drivetrain: drivetrain ?? this.drivetrain,
      displacement: displacement ?? this.displacement,
      transmissionType: transmissionType ?? this.transmissionType,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VehicleProfile) return false;
    if (other.id != id ||
        other.make != make ||
        other.model != model ||
        other.year != year ||
        other.color != color ||
        other.powerKw != powerKw ||
        other.drivetrain != drivetrain ||
        other.displacement != displacement ||
        other.transmissionType != transmissionType) {
      return false;
    }
    if (other.mods.length != mods.length) return false;
    for (var i = 0; i < mods.length; i++) {
      if (other.mods[i] != mods[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        make,
        model,
        year,
        color,
        Object.hashAll(mods),
        powerKw,
        drivetrain,
        displacement,
        transmissionType,
      );
}
