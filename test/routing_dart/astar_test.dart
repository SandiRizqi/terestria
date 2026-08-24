import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_dart/astar.dart';
import 'package:geoform_app/services/routing_dart/graph.dart';
import 'package:geoform_app/services/routing_dart/pbf_reader.dart';

void main() {
  int idx(RoadGraph g, int osmId) => g.indexOfOsmId(osmId)!;

  test('rute lurus A→B→C', () {
    final g = buildGraph(const OsmData(
      [
        OsmNode(1, 1.000, 100.000),
        OsmNode(2, 1.000, 100.001),
        OsmNode(3, 1.000, 100.002),
      ],
      [OsmWay(10, [1, 2, 3], {'highway': 'residential'})],
    ));
    final path = aStar(g, idx(g, 1), idx(g, 3), RouteProfile.car);
    expect(path, [idx(g, 1), idx(g, 2), idx(g, 3)]);
  });

  test('start == goal → path satu titik', () {
    final g = buildGraph(const OsmData(
      [OsmNode(1, 1.0, 100.0), OsmNode(2, 1.0, 100.001)],
      [OsmWay(10, [1, 2], {'highway': 'residential'})],
    ));
    expect(aStar(g, idx(g, 1), idx(g, 1), RouteProfile.car), [idx(g, 1)]);
  });

  test('fastest memilih jalan lebih cepat (speed tinggi) pada diamond simetris', () {
    // A→(B utara)→D residential(30); A→(C selatan)→D secondary(60). Simetris.
    final g = buildGraph(const OsmData(
      [
        OsmNode(1, 1.000, 100.000), // A
        OsmNode(2, 1.001, 100.001), // B utara
        OsmNode(3, 0.999, 100.001), // C selatan
        OsmNode(4, 1.000, 100.002), // D
      ],
      [
        OsmWay(10, [1, 2, 4], {'highway': 'residential'}), // speed 30
        OsmWay(11, [1, 3, 4], {'highway': 'secondary'}), // speed 60
      ],
    ));
    final path = aStar(g, idx(g, 1), idx(g, 4), RouteProfile.car);
    expect(path, [idx(g, 1), idx(g, 3), idx(g, 4)]); // lewat C (60 km/j)
  });

  test('oneway: mobil TIDAK bisa lawan arah; foot BISA', () {
    final g = buildGraph(const OsmData(
      [OsmNode(1, 1.0, 100.0), OsmNode(2, 1.0, 100.001)],
      [OsmWay(10, [1, 2], {'highway': 'residential', 'oneway': 'yes'})],
    ));
    // maju (1→2) boleh mobil
    expect(aStar(g, idx(g, 1), idx(g, 2), RouteProfile.car),
        [idx(g, 1), idx(g, 2)]);
    // balik (2→1) mobil: tak ada jalur
    expect(aStar(g, idx(g, 2), idx(g, 1), RouteProfile.car), isNull);
    // balik (2→1) foot: boleh
    expect(aStar(g, idx(g, 2), idx(g, 1), RouteProfile.foot),
        [idx(g, 2), idx(g, 1)]);
  });

  test('graph terputus → null', () {
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
    expect(aStar(g, idx(g, 1), idx(g, 4), RouteProfile.car), isNull);
  });

  test('profileFromString cocok dgn Android', () {
    expect(profileFromString('car'), RouteProfile.car);
    expect(profileFromString('car_recommended'), RouteProfile.carRecommended);
    expect(profileFromString('foot'), RouteProfile.foot);
    expect(profileFromString('apa_saja'), RouteProfile.car); // default
  });
}
