class GeoPoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final DateTime timestamp;
  final String? fixQuality; // RTK fix quality: fix, float, autonomous, etc.
  final int? satelliteCount; // Number of satellites used

  GeoPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    required this.timestamp,
    this.fixQuality,
    this.satelliteCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
      'fixQuality': fixQuality,
      'satelliteCount': satelliteCount,
    };
  }

  factory GeoPoint.fromJson(Map<String, dynamic> json) {
    return GeoPoint(
      latitude: json['latitude'],
      longitude: json['longitude'],
      altitude: json['altitude'],
      accuracy: json['accuracy'],
      timestamp: DateTime.parse(json['timestamp']),
      fixQuality: json['fixQuality'],
      satelliteCount: json['satelliteCount'],
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
  final String? collectedBy; // username yang mengumpulkan data

  GeoData({
    required this.id,
    required this.projectId,
    required this.formData,
    required this.points,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
    this.syncedAt,
    this.collectedBy,
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
      'collectedBy': collectedBy, // Save as camelCase for local storage consistency
    };
  }

  factory GeoData.fromJson(Map<String, dynamic> json) {
    return GeoData(
      id: json['id'],
      projectId: json['projectId'] ?? json['project_id'], // Support both formats
      formData: json['formData'] ?? json['form_data'] ?? {}, // Support both formats
      points: (json['points'] as List).map((p) => GeoPoint.fromJson(p)).toList(),
      createdAt: DateTime.parse(json['createdAt'] ?? json['created_at']), // Support both formats
      updatedAt: DateTime.parse(json['updatedAt'] ?? json['updated_at']), // Support both formats
      isSynced: json['isSynced'] ?? json['is_synced'] ?? false, // Support both formats
      syncedAt: (json['syncedAt'] ?? json['synced_at']) != null 
          ? DateTime.parse(json['syncedAt'] ?? json['synced_at']) 
          : null,
      collectedBy: json['collectedBy'] ?? json['collected_by'], // Support both snake_case and camelCase
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
    String? collectedBy,
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
      collectedBy: collectedBy ?? this.collectedBy,
    );
  }
}
