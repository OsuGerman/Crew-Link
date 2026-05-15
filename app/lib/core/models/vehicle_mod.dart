/// A single modification on a vehicle (e.g. Performance-Wheels,
/// Sport-Auspuff). `id` is server-assigned: client-side drafts use a
/// temporary string until they round-trip through `PUT /vehicles/me`.
class VehicleMod {
  const VehicleMod({
    required this.id,
    required this.name,
    this.description,
    this.category,
  });

  factory VehicleMod.fromJson(Map<String, Object?> json) {
    return VehicleMod(
      id: json['id']! as String,
      name: json['name']! as String,
      description: json['description'] as String?,
      category: json['category'] as String?,
    );
  }

  final String id;
  final String name;
  final String? description;
  final String? category;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
      };

  /// Body shape for `PUT /vehicles/me` — no id, server assigns on
  /// insert. Empty optional fields are stripped.
  Map<String, Object?> toPutBody() {
    final body = <String, Object?>{'name': name};
    if (description != null && description!.trim().isNotEmpty) {
      body['description'] = description;
    }
    if (category != null && category!.trim().isNotEmpty) {
      body['category'] = category;
    }
    return body;
  }

  VehicleMod copyWith({
    String? name,
    String? description,
    String? category,
  }) {
    return VehicleMod(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VehicleMod &&
          other.id == id &&
          other.name == name &&
          other.description == description &&
          other.category == category;

  @override
  int get hashCode => Object.hash(id, name, description, category);
}
