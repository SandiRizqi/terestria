import 'graph.dart';

/// Profil routing — SAMA dengan Android (GraphHopper): `car`/`foot` = fastest
/// (murni waktu tempuh), `car_recommended` = recommended (waktu + prioritas
/// kelas jalan). Prioritas di sini didekati dari kecepatan (proxy road_class)
/// karena graph menyimpan speed, bukan road_class mentah.
enum RouteProfile { car, carRecommended, foot }

/// Peta string profil (dikirim RoutingService) → enum. Default: car.
RouteProfile profileFromString(String? s) {
  switch (s) {
    case 'foot':
      return RouteProfile.foot;
    case 'car_recommended':
      return RouteProfile.carRecommended;
    case 'car':
    default:
      return RouteProfile.car;
  }
}

/// Kecepatan jalan kaki (km/jam) — dipakai bersama route_builder.
const double footSpeedKmh = 5.0;
const double _hMaxCarKmh = 140.0; // heuristik admissible (tak ada jalan lebih cepat)

/// A* dari [start] ke [goal] (indeks node) untuk [profile].
/// Return urutan indeks node (termasuk start & goal), atau null bila tak ada jalur.
List<int>? aStar(RoadGraph g, int start, int goal, RouteProfile profile) {
  final n = g.nodeCount;
  if (start < 0 || goal < 0 || start >= n || goal >= n) return null;
  if (start == goal) return [start];

  final gScore = List<double>.filled(n, double.infinity);
  final cameFrom = List<int>.filled(n, -1);
  final closed = List<bool>.filled(n, false);
  final goalLat = g.latOf(goal), goalLon = g.lonOf(goal);
  final hMax = profile == RouteProfile.foot ? footSpeedKmh : _hMaxCarKmh;

  double heuristic(int node) =>
      haversineMeters(g.latOf(node), g.lonOf(node), goalLat, goalLon) *
      3.6 /
      hMax;

  final heap = _MinHeap();
  gScore[start] = 0;
  heap.push(heuristic(start), start);

  while (!heap.isEmpty) {
    final u = heap.pop();
    if (closed[u]) continue;
    if (u == goal) return _reconstruct(cameFrom, goal);
    closed[u] = true;

    for (var e = g.csrOffset[u]; e < g.csrOffset[u + 1]; e++) {
      if (profile != RouteProfile.foot && g.edgeCar[e] == 0) continue; // oneway
      final v = g.edgeTarget[e];
      if (closed[v]) continue;
      final tentative = gScore[u] + _edgeCost(profile, g.edgeLength[e], g.edgeSpeed[e]);
      if (tentative < gScore[v]) {
        gScore[v] = tentative;
        cameFrom[v] = u;
        heap.push(tentative + heuristic(v), v);
      }
    }
  }
  return null;
}

/// Edge yang dipakai antara node [u]→[v] untuk [profile]: panjang, speed, nama.
/// Bila ada beberapa edge paralel (jarang) ambil yang termurah waktunya.
/// Fallback haversine + speed 30 bila tak ada edge (seharusnya tak terjadi pada
/// path A* yang valid). Dipakai bersama route_builder & instructions.
({double length, double speed, String name}) segmentBetween(
    RoadGraph g, int u, int v, RouteProfile profile) {
  double? bestLen;
  var bestSpeed = 30.0;
  var bestName = '';
  var bestTime = double.infinity;
  for (final e in g.edgesFrom(u)) {
    if (e.to != v) continue;
    if (profile != RouteProfile.foot && !e.car) continue;
    final spd = profile == RouteProfile.foot ? footSpeedKmh : e.speed;
    final t = e.length * 3.6 / spd;
    if (t < bestTime) {
      bestTime = t;
      bestLen = e.length;
      bestSpeed = e.speed;
      bestName = e.name;
    }
  }
  return (
    length: bestLen ??
        haversineMeters(g.latOf(u), g.lonOf(u), g.latOf(v), g.lonOf(v)),
    speed: bestSpeed,
    name: bestName,
  );
}

/// Biaya edge (detik) sesuai profil.
double _edgeCost(RouteProfile profile, double lengthM, double speedKmh) {
  switch (profile) {
    case RouteProfile.foot:
      return lengthM * 3.6 / footSpeedKmh;
    case RouteProfile.car:
      return lengthM * 3.6 / speedKmh;
    case RouteProfile.carRecommended:
      // recommended: waktu dibagi prioritas (jalan kelas rendah → biaya naik).
      return (lengthM * 3.6 / speedKmh) / _priority(speedKmh);
  }
}

/// Proxy prioritas road_class dari kecepatan (1.0 = paling disukai).
double _priority(double speedKmh) {
  if (speedKmh >= 80) return 1.0;
  if (speedKmh >= 50) return 0.9;
  if (speedKmh >= 30) return 0.8;
  return 0.6;
}

List<int> _reconstruct(List<int> cameFrom, int goal) {
  final path = <int>[goal];
  var cur = goal;
  while (cameFrom[cur] != -1) {
    cur = cameFrom[cur];
    path.add(cur);
  }
  return path.reversed.toList();
}

/// Binary min-heap (paralel: skor f + node), lazy-delete via `closed` di A*.
class _MinHeap {
  final List<double> _f = [];
  final List<int> _n = [];

  bool get isEmpty => _f.isEmpty;

  void push(double f, int node) {
    _f.add(f);
    _n.add(node);
    var i = _f.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_f[p] <= _f[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  int pop() {
    final top = _n[0];
    final last = _f.length - 1;
    _f[0] = _f[last];
    _n[0] = _n[last];
    _f.removeLast();
    _n.removeLast();
    final size = _f.length;
    var i = 0;
    while (true) {
      final l = 2 * i + 1, r = 2 * i + 2;
      var s = i;
      if (l < size && _f[l] < _f[s]) s = l;
      if (r < size && _f[r] < _f[s]) s = r;
      if (s == i) break;
      _swap(i, s);
      i = s;
    }
    return top;
  }

  void _swap(int a, int b) {
    final tf = _f[a];
    _f[a] = _f[b];
    _f[b] = tf;
    final tn = _n[a];
    _n[a] = _n[b];
    _n[b] = tn;
  }
}
