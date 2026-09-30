import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';

/// Hit-test tap langsung pada feature di peta — fungsi murni di ruang piksel
/// layar (bebas zoom & rotasi: bentuk sudah diproyeksikan oleh pemanggil).
///
/// Toleransi dalam piksel logis; default 24 dp ≈ setengah target sentuh
/// 48 dp, agar line tipis & tepi polygon tetap mudah diketuk.
const double defaultHitTolerance = 24;

/// Bentuk feature dalam koordinat layar, membawa [value] yang dikembalikan
/// bila kena.
sealed class HitShape<T> {
  final T value;
  const HitShape(this.value);
}

/// Marker point: kena bila jarak ke [center] ≤ [radius] + toleransi.
class HitPoint<T> extends HitShape<T> {
  final Offset center;
  final double radius;
  const HitPoint(super.value, {required this.center, required this.radius});
}

/// Line: kena bila jarak ke salah satu segmen ≤ toleransi.
class HitLine<T> extends HitShape<T> {
  final List<Offset> points;
  const HitLine(super.value, {required this.points});
}

/// Polygon: kena bila tap di dalam area atau ≤ toleransi dari garis tepi.
class HitPolygon<T> extends HitShape<T> {
  final List<Offset> ring;
  const HitPolygon(super.value, {required this.ring});
}

/// Feature yang kena tap di [tap], berurutan: point (terdekat) → line
/// (terdekat) → polygon (terkecil). Nilai sama → urutan masukan (stabil).
/// Bentuk rusak (line < 2 titik, polygon < 3 titik) diabaikan.
List<T> hitFeatures<T>(
  Offset tap,
  Iterable<HitShape<T>> shapes, {
  double tolerance = defaultHitTolerance,
}) {
  final hits = <_Hit<T>>[];
  var order = 0;
  for (final shape in shapes) {
    final index = order++;
    switch (shape) {
      case HitPoint<T>(:final center, :final radius):
        final d = (tap - center).distance;
        if (d <= radius + tolerance) hits.add(_Hit(shape.value, 0, d, index));
      case HitLine<T>(:final points):
        if (points.length < 2) continue;
        final d = _distanceToPath(tap, points, closed: false);
        if (d <= tolerance) hits.add(_Hit(shape.value, 1, d, index));
      case HitPolygon<T>(:final ring):
        if (ring.length < 3) continue;
        if (_contains(ring, tap) ||
            _distanceToPath(tap, ring, closed: true) <= tolerance) {
          hits.add(_Hit(shape.value, 2, _area(ring), index));
        }
    }
  }
  hits.sort((a, b) {
    final byKind = a.kind.compareTo(b.kind);
    if (byKind != 0) return byKind;
    final byMetric = a.metric.compareTo(b.metric);
    return byMetric != 0 ? byMetric : a.order.compareTo(b.order);
  });
  return [for (final h in hits) h.value];
}

/// Bentuk hit untuk satu feature project; [project] memproyeksikan titik ke
/// piksel layar. Titik kurang untuk geometrinya → null.
HitShape<GeoData>? hitShapeFor(
  GeoData data,
  GeometryType type,
  Offset Function(GeoPoint point) project, {
  required double pointRadius,
}) {
  final pts = data.points;
  switch (type) {
    case GeometryType.point:
      if (pts.isEmpty) return null;
      return HitPoint(data, center: project(pts.first), radius: pointRadius);
    case GeometryType.line:
      if (pts.length < 2) return null;
      return HitLine(data, points: [for (final p in pts) project(p)]);
    case GeometryType.polygon:
      if (pts.length < 3) return null;
      return HitPolygon(data, ring: [for (final p in pts) project(p)]);
  }
}

class _Hit<T> {
  final T value;
  final int kind; // 0 point, 1 line, 2 polygon
  final double metric; // jarak (point/line) atau luas (polygon)
  final int order;
  const _Hit(this.value, this.kind, this.metric, this.order);
}

double _segmentDistance(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared)
      .clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

double _distanceToPath(Offset p, List<Offset> points, {required bool closed}) {
  var best = double.infinity;
  for (var i = 0; i + 1 < points.length; i++) {
    best = math.min(best, _segmentDistance(p, points[i], points[i + 1]));
  }
  if (closed) {
    best = math.min(best, _segmentDistance(p, points.last, points.first));
  }
  return best;
}

/// Ray casting (tepi termasuk dari titik terakhir ke pertama).
bool _contains(List<Offset> ring, Offset p) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Luas (shoelace) — untuk mengurutkan polygon bertumpuk, terkecil dulu.
double _area(List<Offset> ring) {
  var sum = 0.0;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    sum += (ring[j].dx + ring[i].dx) * (ring[j].dy - ring[i].dy);
  }
  return sum.abs() / 2;
}
