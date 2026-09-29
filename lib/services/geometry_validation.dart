import 'dart:math' as math;

import '../models/geo_data_model.dart';
import '../models/project_model.dart';

/// Pemeriksaan kewajaran geometri sebelum disimpan. Hanya PERINGATAN (user
/// tetap boleh menyimpan) — mis. poligon dari tracking sering berpotongan
/// sendiri bila surveyor berjalan balik di sisi yang sama.

const double _earthRadiusM = 6371000.0;

/// Di atas jumlah vertex ini cek potong-sendiri (O(n²)) dilewati agar UI tak
/// tersendat pada track sangat panjang.
const int selfIntersectionCheckLimit = 3000;

class _Xy {
  final double x, y;
  const _Xy(this.x, this.y);
}

/// Proyeksi lokal (meter) relatif centroid — cukup akurat skala lapangan.
List<_Xy> _project(List<GeoPoint> pts) {
  final lat0 =
      pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
  final lon0 =
      pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
  final k = math.pi / 180 * _earthRadiusM;
  final c = math.cos(lat0 * math.pi / 180);
  return [
    for (final p in pts)
      _Xy((p.longitude - lon0) * k * c, (p.latitude - lat0) * k),
  ];
}

/// Vertex berurutan yang identik (≤ 1 cm) — umumnya dari ketukan ganda.
int countDuplicateVertices(List<GeoPoint> pts) {
  if (pts.length < 2) return 0;
  final xy = _project(pts);
  var n = 0;
  for (var i = 1; i < xy.length; i++) {
    final dx = xy[i].x - xy[i - 1].x, dy = xy[i].y - xy[i - 1].y;
    if (dx * dx + dy * dy < 1e-4) n++;
  }
  return n;
}

double _cross(_Xy o, _Xy a, _Xy b) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

bool _segmentsCross(_Xy p1, _Xy p2, _Xy q1, _Xy q2) {
  final d1 = _cross(q1, q2, p1);
  final d2 = _cross(q1, q2, p2);
  final d3 = _cross(p1, p2, q1);
  final d4 = _cross(p1, p2, q2);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// True bila tepi poligon (ring ditutup otomatis) saling berpotongan.
/// Null bila tak diperiksa (vertex > [selfIntersectionCheckLimit]).
bool? polygonSelfIntersects(List<GeoPoint> pts) {
  if (pts.length < 4) return false;
  if (pts.length > selfIntersectionCheckLimit) return null;
  final xy = _project(pts);
  final n = xy.length;
  for (var i = 0; i < n; i++) {
    final a1 = xy[i], a2 = xy[(i + 1) % n];
    for (var j = i + 1; j < n; j++) {
      // Lewati tepi yang bersebelahan (berbagi vertex).
      if (j == i || (j + 1) % n == i || (i + 1) % n == j) continue;
      if (_segmentsCross(a1, a2, xy[j], xy[(j + 1) % n])) return true;
    }
  }
  return false;
}

double _polygonAreaM2(List<_Xy> xy) {
  var sum = 0.0;
  for (var i = 0; i < xy.length; i++) {
    final j = (i + 1) % xy.length;
    sum += xy[i].x * xy[j].y - xy[j].x * xy[i].y;
  }
  return sum.abs() / 2;
}

double _lineLengthM(List<_Xy> xy) {
  var total = 0.0;
  for (var i = 1; i < xy.length; i++) {
    final dx = xy[i].x - xy[i - 1].x, dy = xy[i].y - xy[i - 1].y;
    total += math.sqrt(dx * dx + dy * dy);
  }
  return total;
}

/// Daftar peringatan (English, siap tampil) untuk geometri [type].
List<String> geometryWarnings(GeometryType type, List<GeoPoint> pts) {
  final warnings = <String>[];
  if (pts.isEmpty) return warnings;

  final dups = countDuplicateVertices(pts);
  if (dups > 0 && type != GeometryType.point) {
    warnings.add('$dups duplicate point${dups > 1 ? 's' : ''} '
        '(tapped or recorded twice at the same spot).');
  }

  switch (type) {
    case GeometryType.point:
      break;
    case GeometryType.line:
      if (pts.length >= 2 && _lineLengthM(_project(pts)) < 1.0) {
        warnings.add('The line is shorter than 1 m.');
      }
      break;
    case GeometryType.polygon:
      if (pts.length >= 3) {
        final area = _polygonAreaM2(_project(pts));
        if (area < 1.0) {
          warnings.add('The polygon area is almost zero '
              '(${area.toStringAsFixed(2)} m²).');
        }
        if (polygonSelfIntersects(pts) == true) {
          warnings.add('The polygon edges cross each other. The area may be '
              'wrong — check the points before saving.');
        }
      }
      break;
  }
  return warnings;
}
