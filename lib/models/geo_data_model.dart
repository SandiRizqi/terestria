import 'json_parse.dart';

class GeoPoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed; // km/h
  final DateTime timestamp;
  final String? fixQuality; // RTK fix quality: fix, float, autonomous, etc.
  final int? satelliteCount; // Number of satellites used

  /// Flag RUNTIME (bukan data tersimpan): true = titik ini layak DIREKAM ke
  /// jalur track (lolos warm-up + akurasi + anti-outlier + bukan drift diam).
  /// false = tampilkan sebagai marker saja, JANGAN direkam. Default true agar
  /// titik dari sumber lain (Emlid RTK, data tersimpan) selalu dianggap valid.
  /// SENGAJA tidak masuk [toJson]/[fromJson] — hanya relevan saat live.
  final bool recordable;

  /// Koordinat & akurasi MENTAH (sebelum smoothing Kalman) — runtime saja,
  /// tidak disimpan. Bila ada, [forRecording] memakai nilai ini untuk titik
  /// jalur; [latitude]/[longitude] (smoothing) untuk marker di layar.
  final double? rawLatitude;
  final double? rawLongitude;
  final double? rawAccuracy;

  GeoPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    required this.timestamp,
    this.fixQuality,
    this.satelliteCount,
    this.recordable = true,
    this.rawLatitude,
    this.rawLongitude,
    this.rawAccuracy,
  });

  /// Titik untuk DIREKAM ke jalur: koordinat mentah bila tersedia (tanpa
  /// lag smoothing), tanpa field runtime.
  GeoPoint forRecording() {
    if (rawLatitude == null || rawLongitude == null) return this;
    return GeoPoint(
      latitude: rawLatitude!,
      longitude: rawLongitude!,
      altitude: altitude,
      accuracy: rawAccuracy ?? accuracy,
      speed: speed,
      timestamp: timestamp,
      fixQuality: fixQuality,
      satelliteCount: satelliteCount,
      recordable: recordable,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'speed': speed,
      // UTC eksplisit (akhiran Z) — tak bergeser bila zona waktu HP berubah.
      'timestamp': timestamp.toUtc().toIso8601String(),
      'fixQuality': fixQuality,
      'satelliteCount': satelliteCount,
    };
  }

  /// Toleran: angka boleh int/double/string (server lama), `fixQuality` /
  /// `satelliteCount` boleh camelCase atau snake_case. Lat/lon/timestamp wajib;
  /// bila rusak melempar [FormatException] yang menyebut field-nya.
  factory GeoPoint.fromJson(Map<String, dynamic> json) {
    return GeoPoint(
      latitude: requireDouble(json['latitude'], 'latitude'),
      longitude: requireDouble(json['longitude'], 'longitude'),
      altitude: parseDouble(json['altitude']),
      accuracy: parseDouble(json['accuracy']),
      speed: parseDouble(json['speed']),
      timestamp: requireDateTime(json['timestamp'], 'timestamp'),
      fixQuality: parseString(json['fixQuality'] ?? json['fix_quality']),
      satelliteCount:
          parseInt(json['satelliteCount'] ?? json['satellite_count']),
    );
  }

  GeoPoint copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    double? accuracy,
    double? speed,
    DateTime? timestamp,
    String? fixQuality,
    int? satelliteCount,
    bool? recordable,
  }) {
    return GeoPoint(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      timestamp: timestamp ?? this.timestamp,
      fixQuality: fixQuality ?? this.fixQuality,
      satelliteCount: satelliteCount ?? this.satelliteCount,
      recordable: recordable ?? this.recordable,
      rawLatitude: rawLatitude,
      rawLongitude: rawLongitude,
      rawAccuracy: rawAccuracy,
    );
  }

  @override
  String toString() {
    return 'GeoPoint(lat: $latitude, lng: $longitude, speed: ${speed?.toStringAsFixed(1)} km/h, time: $timestamp)';
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
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'isSynced': isSynced,
      'syncedAt': syncedAt?.toUtc().toIso8601String(),
      'collectedBy': collectedBy, // Save as camelCase for local storage consistency
    };
  }

  /// Mendukung camelCase (lokal) dan snake_case (server). Field wajib yang
  /// rusak melempar [FormatException] yang menyebut field-nya; field opsional
  /// yang rusak diperlakukan sebagai kosong.
  factory GeoData.fromJson(Map<String, dynamic> json) {
    final id = parseString(json['id']);
    final projectId = parseString(json['projectId'] ?? json['project_id']);
    if (id == null) throw const FormatException('Missing "id"');
    if (projectId == null) {
      throw FormatException('Missing "project_id" for record $id');
    }
    final rawForm = json['formData'] ?? json['form_data'];
    final rawPoints = json['points'];
    return GeoData(
      id: id,
      projectId: projectId,
      formData: rawForm is Map ? Map<String, dynamic>.from(rawForm) : {},
      points: rawPoints is List
          ? rawPoints
              .map((p) => GeoPoint.fromJson(Map<String, dynamic>.from(p as Map)))
              .toList()
          : <GeoPoint>[],
      createdAt: requireDateTime(
          json['createdAt'] ?? json['created_at'], 'created_at'),
      updatedAt: requireDateTime(
          json['updatedAt'] ?? json['updated_at'], 'updated_at'),
      isSynced: parseBool(json['isSynced'] ?? json['is_synced']),
      syncedAt: parseDateTime(json['syncedAt'] ?? json['synced_at']),
      collectedBy: parseString(json['collectedBy'] ?? json['collected_by']),
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
