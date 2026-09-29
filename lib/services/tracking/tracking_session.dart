import 'dart:math' as math;

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';

/// Status sesi. Urutan = kode di kolom DB `paused` (0/1/2) — jangan diubah.
enum SessionState {
  /// Menerima titik GPS; menahan service & dihitung cap.
  recording,

  /// Ditahan sementara; dihitung cap, tak menerima titik.
  paused,

  /// Sudah di-Stop, menunggu disimpan/dibuang. Tak dihitung cap, tak menahan
  /// service, tak menerima titik.
  pendingSave,
}

/// Sumber GPS yang merekam sebuah sesi. Diikat saat Start agar jalur RTK tak
/// tercampur titik GPS HP (dan sebaliknya).
enum TrackSource { phone, emlid }

/// Satu sesi tracking untuk sebuah project. Menyimpan titik yang direkam
/// SEJAK [startedAt] dari sumber [source].
class TrackingSession {
  final Project project;
  final DateTime startedAt;
  final List<GeoPoint> points;
  final TrackSource source;
  SessionState state;

  /// Naik setiap edit destruktif (undo/clear) — persistensi append-only lalu
  /// menulis ulang titik sesi ini alih-alih menambah dari posisi basi.
  int editVersion = 0;

  TrackingSession({
    required this.project,
    required this.startedAt,
    List<GeoPoint>? points,
    this.source = TrackSource.phone,
    this.state = SessionState.recording,
  }) : points = points ?? <GeoPoint>[];

  String get projectId => project.id;
  bool get isRecording => state == SessionState.recording;
  bool get paused => state == SessionState.paused;
  bool get pendingSave => state == SessionState.pendingSave;

  /// Masih "hidup" (recording/paused) — dihitung terhadap cap.
  bool get isLive => state != SessionState.pendingSave;
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
