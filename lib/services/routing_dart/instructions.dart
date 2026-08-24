import 'dart:math' as math;

import '../../models/route_result.dart';
import 'astar.dart';
import 'graph.dart';

/// Bangun daftar [RouteInstruction] turn-by-turn dari path A* (indeks node).
///
/// Instruksi baru dibuat saat ADA belokan (sign ≠ continue) ATAU nama jalan
/// berganti. Tiap instruksi mengakumulasi jarak & waktu segmen sampai instruksi
/// berikutnya. `interval` = indeks titik tempat instruksi mulai. Selalu diakhiri
/// instruksi `finish`.
List<RouteInstruction> buildInstructions(
    RoadGraph g, List<int> path, RouteProfile profile) {
  final lastPt = path.length - 1;
  if (path.length < 2) {
    return [
      const RouteInstruction(
          text: 'You have arrived',
          distance: 0,
          time: 0,
          sign: TurnSign.finish,
          interval: 0),
    ];
  }

  final segCount = path.length - 1;
  final bearing = List<double>.filled(segCount, 0);
  final segLen = List<double>.filled(segCount, 0);
  final segTimeMs = List<int>.filled(segCount, 0);
  final segName = List<String>.filled(segCount, '');

  for (var j = 0; j < segCount; j++) {
    final u = path[j], v = path[j + 1];
    bearing[j] = _bearing(g.latOf(u), g.lonOf(u), g.latOf(v), g.lonOf(v));
    final seg = _segment(g, u, v, profile);
    segLen[j] = seg.length;
    segName[j] = seg.name;
    final spd = profile == RouteProfile.foot ? footSpeedKmh : seg.speed;
    segTimeMs[j] = (seg.length * 3.6 / spd * 1000).round();
  }

  // Titik-titik mulai instruksi: (indeksTitik, sign, nama).
  final starts = <({int pt, int sign, String name})>[
    (pt: 0, sign: TurnSign.continueOnStreet, name: segName[0]),
  ];
  for (var i = 1; i < segCount; i++) {
    final delta = _normDelta(bearing[i] - bearing[i - 1]);
    final sign = _signFor(delta);
    final nameChanged = segName[i] != segName[i - 1];
    if (sign != TurnSign.continueOnStreet || nameChanged) {
      starts.add((pt: i, sign: sign, name: segName[i]));
    }
  }

  final out = <RouteInstruction>[];
  for (var k = 0; k < starts.length; k++) {
    final s = starts[k];
    final endPt = (k + 1 < starts.length) ? starts[k + 1].pt : lastPt;
    var dist = 0.0;
    var time = 0;
    for (var j = s.pt; j < endPt; j++) {
      dist += segLen[j];
      time += segTimeMs[j];
    }
    out.add(RouteInstruction(
      text: _text(s.sign, s.name, first: k == 0),
      distance: dist,
      time: time,
      sign: s.sign,
      interval: s.pt,
    ));
  }
  out.add(RouteInstruction(
    text: 'You have arrived',
    distance: 0,
    time: 0,
    sign: TurnSign.finish,
    interval: lastPt,
  ));
  return out;
}

/// Edge yang dilewati u→v (nama/speed/panjang). Sejalan dgn route_builder.
({double length, double speed, String name}) _segment(
    RoadGraph g, int u, int v, RouteProfile profile) {
  double? bestLen;
  double bestSpeed = 30;
  String bestName = '';
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

/// Klasifikasi belokan dari selisih bearing (derajat, +kanan / -kiri).
int _signFor(double delta) {
  final a = delta.abs();
  if (a > 160) return TurnSign.uTurn;
  if (a < 20) return TurnSign.continueOnStreet;
  final right = delta > 0;
  if (a <= 45) return right ? TurnSign.turnSlightRight : TurnSign.turnSlightLeft;
  if (a <= 120) return right ? TurnSign.turnRight : TurnSign.turnLeft;
  return right ? TurnSign.turnSharpRight : TurnSign.turnSharpLeft;
}

String _text(int sign, String name, {required bool first}) {
  final onto = name.isEmpty ? '' : ' onto $name';
  final on = name.isEmpty ? '' : ' on $name';
  switch (sign) {
    case TurnSign.uTurn:
      return 'Make a U-turn$onto';
    case TurnSign.turnSharpLeft:
      return 'Sharp left$onto';
    case TurnSign.turnLeft:
      return 'Turn left$onto';
    case TurnSign.turnSlightLeft:
      return 'Slight left$onto';
    case TurnSign.turnSlightRight:
      return 'Slight right$onto';
    case TurnSign.turnRight:
      return 'Turn right$onto';
    case TurnSign.turnSharpRight:
      return 'Sharp right$onto';
    case TurnSign.finish:
      return 'You have arrived';
    case TurnSign.continueOnStreet:
    default:
      if (first) return name.isEmpty ? 'Head out' : 'Continue$on';
      return name.isEmpty ? 'Continue' : 'Continue$onto';
  }
}

/// Bearing awal dari (lat1,lon1) ke (lat2,lon2), derajat 0..360 (0 = utara).
double _bearing(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = _rad(lat1), phi2 = _rad(lat2);
  final dLon = _rad(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  final deg = math.atan2(y, x) * 180 / math.pi;
  return (deg + 360) % 360;
}

/// Normalisasi selisih bearing ke (-180, 180].
double _normDelta(double d) {
  var x = d;
  while (x > 180) {
    x -= 360;
  }
  while (x <= -180) {
    x += 360;
  }
  return x;
}

double _rad(double deg) => deg * math.pi / 180.0;
