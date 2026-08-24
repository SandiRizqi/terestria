import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_dart/graph.dart';
import 'package:geoform_app/services/routing_dart/pbf_reader.dart';
import 'package:geoform_app/services/routing_dart/snapper.dart';

void main() {
  // Segmen meridian: node1(1.000,100.0) → node2(1.002,100.0) (~222 m ke utara).
  RoadGraph lineGraph() => buildGraph(const OsmData(
        [OsmNode(1, 1.000, 100.0), OsmNode(2, 1.002, 100.0)],
        [OsmWay(10, [1, 2], {'highway': 'residential'})],
      ));

  test('snap titik di samping tengah → proyeksi ke tengah segmen', () {
    final g = lineGraph();
    // ~10 m timur titik tengah (lat 1.001). Proyeksi balik ke meridian lon=100.0.
    final r = snap(g, 1.001, 100.00009)!;
    expect(r.distanceMeters, closeTo(10, 3));
    expect(r.snappedLon, closeTo(100.0, 1e-5));
    expect(r.snappedLat, closeTo(1.001, 1e-4));
    expect(r.t, closeTo(0.5, 0.05));
  });

  test('titik di luar ujung → clamp ke node ujung', () {
    final g = lineGraph();
    final r = snap(g, 0.999, 100.0)!; // di selatan node1 (lat 1.000)
    expect(r.snappedLat, closeTo(1.000, 1e-6));
    expect(r.snappedLon, closeTo(100.0, 1e-6));
    expect(r.t == 0.0 || r.t == 1.0, isTrue);
  });

  test('graph tanpa edge → null', () {
    final g = buildGraph(const OsmData([], []));
    expect(snap(g, 1.0, 100.0), isNull);
  });

  test('memilih edge terdekat di antara beberapa', () {
    // Dua ruas terpisah; query dekat ruas kedua.
    final g = buildGraph(const OsmData(
      [
        OsmNode(1, 1.0, 100.0),
        OsmNode(2, 1.0, 100.001),
        OsmNode(3, 2.0, 100.0),
        OsmNode(4, 2.0, 100.001),
      ],
      [
        OsmWay(10, [1, 2], {'highway': 'residential'}),
        OsmWay(11, [3, 4], {'highway': 'residential'}),
      ],
    ));
    final r = snap(g, 2.0, 100.0005)!; // di ruas kedua (lat 2.0)
    expect(r.snappedLat, closeTo(2.0, 1e-4));
  });
}
