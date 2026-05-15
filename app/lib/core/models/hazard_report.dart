/// Kategorie einer Gefahrenmeldung. Bewusst KEINE Blitzer/Geschwindigkeits-
/// kontrollen — diese sind in DE während der Fahrt nicht zulässig (StVO § 23
/// Abs. 1c). Erlaubt sind ausschließlich Sicherheitshinweise zu Verkehrslage,
/// Hindernissen und Witterung.
enum HazardType {
  construction,
  accident,
  trafficJam,
  brokenDownVehicle,
  obstacle,
  poorVisibility,
  slipperyRoad,
  policeCheckpoint,
  other;

  String get wireValue {
    switch (this) {
      case HazardType.construction:
        return 'construction';
      case HazardType.accident:
        return 'accident';
      case HazardType.trafficJam:
        return 'traffic_jam';
      case HazardType.brokenDownVehicle:
        return 'broken_down_vehicle';
      case HazardType.obstacle:
        return 'obstacle';
      case HazardType.poorVisibility:
        return 'poor_visibility';
      case HazardType.slipperyRoad:
        return 'slippery_road';
      case HazardType.policeCheckpoint:
        return 'police_checkpoint';
      case HazardType.other:
        return 'other';
    }
  }

  static HazardType fromWire(String wire) {
    for (final t in HazardType.values) {
      if (t.wireValue == wire) return t;
    }
    return HazardType.other;
  }
}

/// Eine einzelne Gefahrenmeldung an einem Geo-Punkt. Wird vom Reporter
/// erstellt, optional auf einen Konvoi beschränkt, und läuft nach
/// `expiresAt` ab (oder ohne Ablauf, wenn `null`). Drafts vor dem
/// Server-Roundtrip nutzen eine clientseitige id (`draft-…`).
class HazardReport {
  const HazardReport({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.reporterId,
    required this.createdAt,
    this.convoyId,
    this.description,
    this.expiresAt,
  });

  factory HazardReport.fromJson(Map<String, Object?> json) {
    return HazardReport(
      id: json['id']! as String,
      type: HazardType.fromWire(json['type']! as String),
      latitude: (json['latitude']! as num).toDouble(),
      longitude: (json['longitude']! as num).toDouble(),
      reporterId: json['reporterId']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      convoyId: json['convoyId'] as String?,
      description: json['description'] as String?,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt']! as String),
    );
  }

  final String id;
  final HazardType type;
  final double latitude;
  final double longitude;
  final String reporterId;
  final DateTime createdAt;
  final String? convoyId;
  final String? description;
  final DateTime? expiresAt;

  bool isActiveAt(DateTime moment) {
    final expiry = expiresAt;
    if (expiry == null) return true;
    return moment.isBefore(expiry);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.wireValue,
        'latitude': latitude,
        'longitude': longitude,
        'reporterId': reporterId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (convoyId != null) 'convoyId': convoyId,
        if (description != null) 'description': description,
        if (expiresAt != null)
          'expiresAt': expiresAt!.toUtc().toIso8601String(),
      };

  /// Body shape for `POST /hazards` — server vergibt id und createdAt.
  Map<String, Object?> toPostBody() {
    final body = <String, Object?>{
      'type': type.wireValue,
      'latitude': latitude,
      'longitude': longitude,
    };
    if (convoyId != null) body['convoyId'] = convoyId;
    if (description != null && description!.trim().isNotEmpty) {
      body['description'] = description;
    }
    if (expiresAt != null) {
      body['expiresAt'] = expiresAt!.toUtc().toIso8601String();
    }
    return body;
  }

  HazardReport copyWith({
    HazardType? type,
    double? latitude,
    double? longitude,
    String? convoyId,
    String? description,
    DateTime? expiresAt,
  }) {
    return HazardReport(
      id: id,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      reporterId: reporterId,
      createdAt: createdAt,
      convoyId: convoyId ?? this.convoyId,
      description: description ?? this.description,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HazardReport &&
          other.id == id &&
          other.type == type &&
          other.latitude == latitude &&
          other.longitude == longitude &&
          other.reporterId == reporterId &&
          other.createdAt == createdAt &&
          other.convoyId == convoyId &&
          other.description == description &&
          other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(
        id,
        type,
        latitude,
        longitude,
        reporterId,
        createdAt,
        convoyId,
        description,
        expiresAt,
      );
}
