import 'dart:math' as math;

import 'graph.dart';

/// Hasil snap sebuah titik query ke jaringan jalan.
class SnapResult {
  /// Node awal & akhir edge (terarah) tempat titik diproyeksikan.
  final int fromNode;
  final int toNode;

  /// Titik proyeksi pada edge (koordinat).
  final double snappedLat;
  final double snappedLon;

  /// Jarak dari query ke titik proyeksi (meter).
  final double distanceMeters;

  /// Posisi sepanjang edge fromNode→toNode, 0..1.
  final double t;

  const SnapResult({
    required this.fromNode,
    required this.toNode,
    required this.snappedLat,
    required this.snappedLon,
    required this.distanceMeters,
    required this.t,
  });
}

/// Cari edge terdekat ke ([qLat],[qLon]) dan proyeksikan titik ke edge itu.
/// Null bila graph tak punya edge. MVP: linear scan (cukup untuk one-shot;
/// spatial index bisa ditambah bila skala menuntut).
SnapResult? snap(RoadGraph g, double qLat, double qLon) {
  // Proyeksi di ruang lokal ter-skala (lon dikali cos(lat)) agar mendekati
  // planar meter; jarak final tetap dihitung haversine.
  final cosLat = math.cos(qLat * math.pi / 180.0);
  final qx = qLon * cosLat, qy = qLat;

  var best = double.infinity;
  var bu = -1, bv = -1;
  var bLat = 0.0, bLon = 0.0, bt = 0.0;

  for (var u = 0; u < g.nodeCount; u++) {
    final aLat = g.latOf(u), aLon = g.lonOf(u);
    final ax = aLon * cosLat, ay = aLat;
    for (var e = g.csrOffset[u]; e < g.csrOffset[u + 1]; e++) {
      final v = g.edgeTarget[e];
      final vLat = g.latOf(v), vLon = g.lonOf(v);
      final bx = vLon * cosLat, by = vLat;

      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = len2 > 0 ? ((qx - ax) * dx + (qy - ay) * dy) / len2 : 0.0;
      if (t < 0) {
        t = 0;
      } else if (t > 1) {
        t = 1;
      }
      final pLat = aLat + t * (vLat - aLat);
      final pLon = aLon + t * (vLon - aLon);
      final d = haversineMeters(qLat, qLon, pLat, pLon);
      if (d < best) {
        best = d;
        bu = u;
        bv = v;
        bLat = pLat;
        bLon = pLon;
        bt = t;
      }
    }
  }

  if (bu < 0) return null;
  return SnapResult(
    fromNode: bu,
    toNode: bv,
    snappedLat: bLat,
    snappedLon: bLon,
    distanceMeters: best,
    t: bt,
  );
}
