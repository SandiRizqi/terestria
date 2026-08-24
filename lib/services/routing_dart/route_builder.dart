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
    final seg = segmentBetween(g, path[i], path[i + 1], profile);
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
