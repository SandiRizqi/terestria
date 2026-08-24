import 'dart:io';
import 'dart:isolate';

import '../../models/route_result.dart';
import 'astar.dart';
import 'graph.dart';
import 'instructions.dart';
import 'pbf_reader.dart';
import 'route_builder.dart';
import 'snapper.dart';

/// Facade mesin routing offline pure-Dart (iOS). Meniru API yang dipakai
/// `RoutingService` Android: [initialize], [isInitialized], [calculateRoute] —
/// sehingga wiring iOS (T8) cukup delegasi tanpa mengubah UI/navigasi.
///
/// Parsing `.pbf` + pembangunan graph (berat) dijalankan di ISOLATE agar UI tak
/// nge-freeze. Pencarian rute (snap+A*) jalan di isolate utama (cepat, one-shot);
/// bila perlu bisa dipindah ke isolate persisten nanti (skala besar).
class DartRoutingEngine {
  RoadGraph? _graph;

  bool get isInitialized => _graph != null;

  /// Muat & bangun graph dari file `.osm.pbf`. Return true bila siap.
  /// Idempoten: bila sudah terinisialisasi, di-skip kecuali [forceRebuild].
  Future<bool> initialize(String pbfPath, {bool forceRebuild = false}) async {
    if (isInitialized && !forceRebuild) return true;
    try {
      final bytes = await File(pbfPath).readAsBytes();
      _graph = await Isolate.run(() => buildGraph(readOsmPbf(bytes)));
      return _graph != null;
    } catch (e) {
      _graph = null;
      return false;
    }
  }

  /// Hitung rute dari (from) ke (to) untuk [profile] (car/car_recommended/foot).
  /// Null bila belum init, titik tak bisa di-snap, atau tak ada jalur.
  Future<RouteResult?> calculateRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    String? profile,
  }) async {
    final g = _graph;
    if (g == null) return null;

    final prof = profileFromString(profile);
    final from = snap(g, fromLat, fromLon);
    final to = snap(g, toLat, toLon);
    if (from == null || to == null) return null;

    // Masuk/keluar graph lewat ujung edge yang lebih dekat ke titik snap.
    final startNode = from.t <= 0.5 ? from.fromNode : from.toNode;
    final goalNode = to.t <= 0.5 ? to.fromNode : to.toNode;

    final path = aStar(g, startNode, goalNode, prof);
    if (path == null) return null;

    final base = buildRouteResult(g, path, prof);
    final instr = buildInstructions(g, path, prof);
    return RouteResult(
      points: base.points,
      instructions: instr,
      distance: base.distance,
      time: base.time,
    );
  }

  /// Lepaskan graph (mis. saat ganti data/company).
  void dispose() => _graph = null;
}
