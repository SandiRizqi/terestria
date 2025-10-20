class GeoPoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final DateTime timestamp;

  GeoPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory GeoPoint.fromJson(Map<String, dynamic> json) {
    return GeoPoint(
      latitude: json['latitude'],
      longitude: json['longitude'],
      altitude: json['altitude'],
      accuracy: json['accuracy'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class GeoData {
  final String id;
  final String projectId;
  final Map<String, dynamic> formData;
  final List<GeoPoint> points; // untuk point, line, atau polygon
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final DateTime? syncedAt;

  GeoData({
    required this.id,
    required this.projectId,
    required this.formData,
    required this.points,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
    this.syncedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'formData': formData,
      'points': points.map((p) => p.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isSynced': isSynced,
      'syncedAt': syncedAt?.toIso8601String(),
    };
  }

  factory GeoData.fromJson(Map<String, dynamic> json) {
    return GeoData(
      id: json['id'],
      projectId: json['projectId'],
      formData: json['formData'],
      points: (json['points'] as List).map((p) => GeoPoint.fromJson(p)).toList(),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      isSynced: json['isSynced'] ?? false,
      syncedAt: json['syncedAt'] != null ? DateTime.parse(json['syncedAt']) : null,
    );
  }

  // Method untuk membuat copy dengan update sync status
  GeoData copyWith({
    String? id,
    String? projectId,
    Map<String, dynamic>? formData,
    List<GeoPoint>? points,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    DateTime? syncedAt,
  }) {
    return GeoData(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      formData: formData ?? this.formData,
      points: points ?? this.points,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}
