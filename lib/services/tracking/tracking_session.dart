import 'dart:math' as math;

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';

/// Satu sesi tracking aktif untuk sebuah project. Menyimpan titik yang direkam
/// SEJAK [startedAt] (fan-out dari satu stream GPS). [paused] menahan penambahan
/// titik tanpa menutup sesi.
class TrackingSession {
  final Project project;
  final DateTime startedAt;
  final List<GeoPoint> points;
  bool paused;

  TrackingSession({
    required this.project,
    required this.startedAt,
    List<GeoPoint>? points,
    this.paused = false,
  }) : points = points ?? <GeoPoint>[];

  String get projectId => project.id;
  int get pointCount => points.length;

  /// Panjang jalur (meter) dari titik yang terekam (haversine berurutan).
  double get distanceMeters {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _haversineMeters(points[i - 1], points[i]);
    }
    return total;
  }

  static double _haversineMeters(GeoPoint a, GeoPoint b) {
    const r = 6371000.0; // radius bumi (m)
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final la1 = _rad(a.latitude);
    final la2 = _rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
