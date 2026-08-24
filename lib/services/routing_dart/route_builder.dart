import '../../models/route_result.dart';
import 'astar.dart';
import 'graph.dart';

/// Rakit path A* (indeks node) → [RouteResult]: geometri + total jarak (m) +
/// total waktu (ms). Instruksi turn-by-turn diisi terpisah (T6) lalu digabung
/// oleh facade. Waktu memakai kecepatan sesuai profil: mobil = speed edge,
/// foot = [footSpeedKmh] (bukan cost recommended — ETA harus waktu nyata).
RouteResult buildRouteResult(
    RoadGraph g, List<int> path, RouteProfile profile) {
  final points = <RoutePoint>[
    for (final n in path) RoutePoint(g.latOf(n), g.lonOf(n)),
  ];

  var distanceM = 0.0;
  var timeSec = 0.0;
  for (var i = 0; i + 1 < path.length; i++) {
    final u = path[i], v = path[i + 1];
    final seg = _segment(g, u, v, profile);
    distanceM += seg.length;
    final spd = profile == RouteProfile.foot ? footSpeedKmh : seg.speed;
    timeSec += seg.length * 3.6 / spd;
  }

  return RouteResult(
    points: points,
    instructions: const [],
    distance: distanceM,
    time: (timeSec * 1000).round(),
  );
}

/// Edge yang dipakai antara node [u]→[v]. Pilih yang bisa dilewati profil;
/// bila ada beberapa (paralel, jarang) ambil yang termurah waktunya. Fallback
/// haversine + speed 30 bila edge tak ditemukan (seharusnya tak terjadi).
({double length, double speed}) _segment(
    RoadGraph g, int u, int v, RouteProfile profile) {
  double? bestLen;
  double bestSpeed = 30;
  double bestTime = double.infinity;
  for (final e in g.edgesFrom(u)) {
    if (e.to != v) continue;
    if (profile != RouteProfile.foot && !e.car) continue;
    final spd = profile == RouteProfile.foot ? footSpeedKmh : e.speed;
    final t = e.length * 3.6 / spd;
    if (t < bestTime) {
      bestTime = t;
      bestLen = e.length;
      bestSpeed = e.speed;
    }
  }
  if (bestLen != null) return (length: bestLen, speed: bestSpeed);
  return (length: haversineMeters(g.latOf(u), g.lonOf(u), g.latOf(v), g.lonOf(v)), speed: 30);
}
