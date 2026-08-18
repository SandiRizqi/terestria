import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Geometri pengukuran murni (tanpa Flutter/UI) untuk map tools bersama.
/// Semua sudut dalam derajat; jarak/luas dalam meter / meter².

const double _earthRadiusM = 6371000.0;
const double _deg2rad = math.pi / 180.0;

/// Jarak great-circle (haversine) antara dua titik, meter.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final dLat = (lat2 - lat1) * _deg2rad;
  final dLon = (lon2 - lon1) * _deg2rad;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * _deg2rad) *
          math.cos(lat2 * _deg2rad) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return _earthRadiusM * 2 * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Total panjang polyline (meter). 0 bila titik < 2.
double polylineLengthMeters(List<LatLng> pts) {
  if (pts.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < pts.length - 1; i++) {
    total += haversineMeters(
        pts[i].latitude, pts[i].longitude, pts[i + 1].latitude, pts[i + 1].longitude);
  }
  return total;
}

/// Luas polygon (meter²) via proyeksi equirectangular terhadap centroid lalu
/// shoelace. Akurat pada skala lapangan (khususnya dekat khatulistiwa).
/// 0 bila titik < 3. Tidak bergantung arah (nilai absolut).
double polygonAreaSqMeters(List<LatLng> pts) {
  if (pts.length < 3) return 0;
  final lat0 =
      pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length * _deg2rad;
  final lon0 =
      pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
  // Proyeksikan ke bidang lokal (meter) relatif centroid.
  final xs = <double>[];
  final ys = <double>[];
  for (final p in pts) {
    xs.add(_earthRadiusM * (p.longitude - lon0) * _deg2rad * math.cos(lat0));
    ys.add(_earthRadiusM * (p.latitude - (lat0 / _deg2rad)) * _deg2rad);
  }
  var sum = 0.0;
  final n = pts.length;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    sum += xs[i] * ys[j] - xs[j] * ys[i];
  }
  return sum.abs() / 2.0;
}

/// Azimuth awal dari titik 1 ke titik 2, derajat [0, 360) dari utara.
double initialBearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * _deg2rad;
  final phi2 = lat2 * _deg2rad;
  final dLon = (lon2 - lon1) * _deg2rad;
  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  final deg = math.atan2(y, x) / _deg2rad;
  return (deg + 360.0) % 360.0;
}

/// Luas lingkaran (meter²) untuk tool radius/buffer.
double circleAreaSqMeters(double radiusMeters) =>
    math.pi * radiusMeters * radiusMeters;
