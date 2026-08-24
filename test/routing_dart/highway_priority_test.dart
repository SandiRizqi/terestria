import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_dart/astar.dart';
import 'package:geoform_app/services/routing_dart/graph.dart';
import 'package:geoform_app/services/routing_dart/pbf_reader.dart';

void main() {
  int idx(RoadGraph g, int id) => g.indexOfOsmId(id)!;

  test('graph menyimpan jenis highway per edge', () {
    final g = buildGraph(const OsmData(
      [OsmNode(1, 1.0, 100.0), OsmNode(2, 1.0, 100.001)],
      [OsmWay(10, [1, 2], {'highway': 'track'})],
    ));
    expect(g.edgesFrom(idx(g, 1)).first.highway, 'track');
  });

  test('maxspeed TIDAK menimpa jenis highway (highway tetap tersimpan)', () {
    final g = buildGraph(const OsmData(
      [OsmNode(1, 1.0, 100.0), OsmNode(2, 1.0, 100.001)],
      [OsmWay(10, [1, 2], {'highway': 'residential', 'maxspeed': '60'})],
    ));
    final e = g.edgesFrom(idx(g, 1)).first;
    expect(e.highway, 'residential'); // tipe dipertahankan
    expect(e.speed, 60); // speed tetap dari maxspeed (untuk ETA)
  });

  test('recommended memilih kelas jalan lebih tinggi walau SPEED sama', () {
    // Diamond simetris; KEDUA jalur maxspeed 30 (speed sama) tapi kelas beda:
    // residential (disukai) vs track (dihindari). fastest tak bisa bedakan;
    // recommended harus lewat residential.
    final g = buildGraph(const OsmData(
      [
        OsmNode(1, 1.000, 100.000), // A
        OsmNode(2, 1.001, 100.001), // B utara
        OsmNode(3, 0.999, 100.001), // C selatan
        OsmNode(4, 1.000, 100.002), // D
      ],
      [
        OsmWay(10, [1, 2, 4], {'highway': 'residential', 'maxspeed': '30'}),
        OsmWay(11, [1, 3, 4], {'highway': 'track', 'maxspeed': '30'}),
      ],
    ));
    final rec = aStar(g, idx(g, 1), idx(g, 4), RouteProfile.carRecommended);
    expect(rec, [idx(g, 1), idx(g, 2), idx(g, 4)]); // lewat B (residential)
  });

  test('integrasi: highway terbaca dari fixture .pbf', () {
    // fixture way 10 [1,2,3] highway=residential (dari generate_fixture.py)
    final bytes = File('test/routing_dart/fixtures/tiny_roads.osm.pbf')
        .readAsBytesSync();
    final g = buildGraph(readOsmPbf(bytes));
    expect(g.edgesFrom(idx(g, 1)).first.highway, 'residential');
  });
}
