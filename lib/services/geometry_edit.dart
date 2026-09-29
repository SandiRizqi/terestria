import 'dart:math' as math;

import '../models/geo_data_model.dart';
import '../models/project_model.dart';

/// Model edit vertex berbasis crosshair (koreksi geometri tanpa mengambil
/// ulang di lokasi): pilih vertex → pindahkan ke crosshair, sisipkan vertex
/// baru setelahnya, atau hapus. Setiap langkah bisa di-undo.
///
/// Vertex yang dipindah/disisipkan adalah titik manual (seperti titik
/// crosshair di layar koleksi): tanpa akurasi GPS, kualitas fix, atau
/// altitude.
class GeometryEditSession {
  GeometryEditSession(this.type, List<GeoPoint> original)
      : original = List.unmodifiable(original),
        _points = List.of(original),
        _selected = original.isEmpty ? null : 0;

  final GeometryType type;
  final List<GeoPoint> original;
  List<GeoPoint> _points;
  int? _selected;
  final List<({List<GeoPoint> points, int? selected})> _undo = [];

  /// Batas riwayat undo (edit sangat panjang tak menghabiskan memori).
  static const maxUndo = 100;

  List<GeoPoint> get points => List.unmodifiable(_points);
  int get length => _points.length;
  int? get selected => _selected;
  GeoPoint? get selectedPoint =>
      _selected == null ? null : _points[_selected!];
  bool get canUndo => _undo.isNotEmpty;
  bool get isDirty => !samePositions(_points, original);

  static int minPoints(GeometryType t) => switch (t) {
        GeometryType.point => 1,
        GeometryType.line => 2,
        GeometryType.polygon => 3,
      };

  bool get canMove => _selected != null;
  bool get canInsert => type != GeometryType.point;
  bool get canDelete =>
      type != GeometryType.point &&
      _selected != null &&
      _points.length > minPoints(type);
  bool get hasEnoughPoints => _points.length >= minPoints(type);

  static bool samePositions(List<GeoPoint> a, List<GeoPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude ||
          a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  void _checkpoint() {
    _undo.add((points: List.of(_points), selected: _selected));
    if (_undo.length > maxUndo) _undo.removeAt(0);
  }

  static GeoPoint _manual(double lat, double lon, DateTime at) =>
      GeoPoint(latitude: lat, longitude: lon, timestamp: at);

  void select(int? index) {
    if (index != null && (index < 0 || index >= _points.length)) return;
    _selected = index;
  }

  /// Pilih vertex berikutnya/sebelumnya (melingkar untuk poligon).
  void selectNext() => _step(1);
  void selectPrevious() => _step(-1);

  void _step(int delta) {
    if (_points.isEmpty) return;
    final cur = _selected;
    if (cur == null) {
      _selected = delta > 0 ? 0 : _points.length - 1;
      return;
    }
    var next = cur + delta;
    if (type == GeometryType.polygon) {
      next %= _points.length;
      if (next < 0) next += _points.length;
    } else {
      next = next.clamp(0, _points.length - 1);
    }
    _selected = next;
  }

  /// Pindahkan vertex terpilih ke [lat]/[lon] (posisi crosshair).
  bool moveSelectedTo(double lat, double lon, {DateTime? at}) {
    final i = _selected;
    if (i == null) return false;
    final p = _points[i];
    if (p.latitude == lat && p.longitude == lon) return false;
    _checkpoint();
    _points[i] = _manual(lat, lon, at ?? DateTime.now());
    return true;
  }

  /// Sisipkan vertex di [lat]/[lon] SETELAH vertex terpilih (atau di akhir
  /// bila tak ada yang dipilih); vertex baru menjadi terpilih.
  bool insertAfterSelected(double lat, double lon, {DateTime? at}) {
    if (!canInsert) return false;
    _checkpoint();
    final index = _selected == null ? _points.length : _selected! + 1;
    _points.insert(index, _manual(lat, lon, at ?? DateTime.now()));
    _selected = index;
    return true;
  }

  /// Hapus vertex terpilih (tak boleh di bawah jumlah minimal geometri).
  bool deleteSelected() {
    final i = _selected;
    if (i == null || !canDelete) return false;
    _checkpoint();
    _points.removeAt(i);
    _selected = _points.isEmpty ? null : math.min(i, _points.length - 1);
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    final last = _undo.removeLast();
    _points = List.of(last.points);
    _selected = last.selected;
    return true;
  }

  /// Kembali ke geometri asli (bisa di-undo).
  void reset() {
    if (!isDirty) return;
    _checkpoint();
    _points = List.of(original);
    _selected = _points.isEmpty ? null : 0;
  }

  /// Vertex terdekat ke [lat]/[lon] dalam [maxMeters], atau null.
  int? nearestVertex(double lat, double lon, {double maxMeters = 30}) {
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < _points.length; i++) {
      final d = _metersBetween(lat, lon, _points[i].latitude, _points[i].longitude);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return bestD <= maxMeters ? best : null;
  }

  static double _metersBetween(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
  }
}
