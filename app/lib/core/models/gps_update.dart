class GpsUpdate {
  const GpsUpdate({
    required this.memberId,
    required this.latitude,
    required this.longitude,
    required this.headingDegrees,
    required this.speedMps,
    required this.timestamp,
    this.accuracyMeters,
  });

  factory GpsUpdate.fromJson(Map<String, Object?> json) {
    return GpsUpdate(
      memberId: json['memberId']! as String,
      latitude: (json['latitude']! as num).toDouble(),
      longitude: (json['longitude']! as num).toDouble(),
      headingDegrees: (json['heading']! as num).toDouble(),
      speedMps: (json['speed']! as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']! as String),
      accuracyMeters: (json['accuracy'] as num?)?.toDouble(),
    );
  }

  final String memberId;
  final double latitude;
  final double longitude;
  final double headingDegrees;
  final double speedMps;
  final DateTime timestamp;
  final double? accuracyMeters;

  Map<String, Object?> toJson() => {
        'memberId': memberId,
        'latitude': latitude,
        'longitude': longitude,
        'heading': headingDegrees,
        'speed': speedMps,
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (accuracyMeters != null) 'accuracy': accuracyMeters,
      };
}
