import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/settings/app_settings.dart';
import 'measure_math.dart';

/// Mode alat ukur peta. `none` = tak ada tool aktif (tap tidak dikonsumsi).
enum MapToolMode { none, distance, area, bearing, coordinate, radius }

/// State + hasil turunan untuk map tools bersama. Widget mendengarkan melalui
/// [ChangeNotifier] agar hanya layer/panel yang rebuild, bukan seluruh layar.
///
/// Semua pengukuran bersifat sementara (scratch) — titik hilang saat `clear()`
/// atau ganti mode; tidak disimpan sebagai data.
class MapToolsController extends ChangeNotifier {
  MapToolMode _mode = MapToolMode.none;
  final List<LatLng> _points = [];

  MapToolMode get mode => _mode;
  bool get isActive => _mode != MapToolMode.none;
  List<LatLng> get points => List.unmodifiable(_points);

  /// Batas jumlah titik per mode (distance/area tak terbatas).
  int get _cap {
    switch (_mode) {
      case MapToolMode.coordinate:
        return 1;
      case MapToolMode.bearing:
      case MapToolMode.radius:
        return 2;
      case MapToolMode.distance:
      case MapToolMode.area:
      case MapToolMode.none:
        return 1 << 30;
    }
  }

  void setMode(MapToolMode m) {
    _mode = m;
    _points.clear();
    notifyListeners();
  }

  /// Toggle: menekan mode aktif yang sama → kembali ke `none`.
  void toggleMode(MapToolMode m) => setMode(_mode == m ? MapToolMode.none : m);

  /// Tambah titik (diabaikan bila tak ada tool aktif). Membuang titik terlama
  /// bila melebihi cap mode.
  void addPoint(LatLng p) {
    if (!isActive) return;
    _points.add(p);
    while (_points.length > _cap) {
      _points.removeAt(0);
    }
    notifyListeners();
  }

  void undo() {
    if (_points.isEmpty) return;
    _points.removeLast();
    notifyListeners();
  }

  void clear() {
    if (_points.isEmpty) return;
    _points.clear();
    notifyListeners();
  }

  // ─── Hasil turunan ──────────────────────────────────────────────────────

  double get lengthMeters => polylineLengthMeters(_points);

  double get areaMeters => polygonAreaSqMeters(_points);

  /// Keliling polygon (ring tertutup). 0 bila < 3 titik.
  double get perimeterMeters {
    if (_points.length < 3) return 0;
    return polylineLengthMeters([..._points, _points.first]);
  }

  /// Azimuth titik pertama → kedua, atau null bila belum 2 titik.
  double? get bearingDeg {
    if (_points.length < 2) return null;
    return initialBearingDeg(_points[0].latitude, _points[0].longitude,
        _points[1].latitude, _points[1].longitude);
  }

  /// Jarak antara dua titik pertama (untuk mode bearing/radius).
  double? get twoPointDistanceMeters {
    if (_points.length < 2) return null;
    return haversineMeters(_points[0].latitude, _points[0].longitude,
        _points[1].latitude, _points[1].longitude);
  }

  /// Radius lingkaran (mode radius): jarak center→edge. Null bila belum 2 titik.
  double? get radiusMeters =>
      _mode == MapToolMode.radius ? twoPointDistanceMeters : null;

  LatLng? get lastPoint => _points.isEmpty ? null : _points.last;

  /// Teks hasil siap tampil, memakai unit dari [settings].
  String resultText(AppSettings settings) {
    switch (_mode) {
      case MapToolMode.none:
        return '';
      case MapToolMode.distance:
        if (_points.length < 2) return 'Tap points to measure length';
        return 'Length: ${settings.formatDistance(lengthMeters)}';
      case MapToolMode.area:
        if (_points.length < 3) return 'Tap ≥3 points to measure area';
        return 'Area: ${settings.formatArea(areaMeters)} • '
            'Perimeter: ${settings.formatDistance(perimeterMeters)}';
      case MapToolMode.bearing:
        final b = bearingDeg;
        if (b == null) return 'Tap 2 points for bearing';
        return 'Bearing: ${b.toStringAsFixed(1)}° • '
            '${settings.formatDistance(twoPointDistanceMeters!)}';
      case MapToolMode.coordinate:
        final p = lastPoint;
        if (p == null) return 'Tap a point to read its coordinate';
        return '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';
      case MapToolMode.radius:
        final r = radiusMeters;
        if (r == null) return 'Tap center then edge';
        return 'Radius: ${settings.formatDistance(r)} • '
            'Area: ${settings.formatArea(circleAreaSqMeters(r))}';
    }
  }
}
