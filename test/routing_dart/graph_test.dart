import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_dart/pbf_reader.dart';
import 'package:geoform_app/services/routing_dart/graph.dart';

void main() {
  group('buildGraph — logika edge', () {
    // Dua node ~157 m terpisah (0.001° lat ≈ 111 m; pakai jarak diketahui).
    OsmData data({
      String? maxspeed,
      String? oneway,
      String highway = 'residential',
      String name = 'Jl A',
    }) =>
        OsmData(
          [const OsmNode(1, 1.0, 100.0), const OsmNode(2, 1.001, 100.0)],
          [
            OsmWay(10, [1, 2], {
              'highway': highway,
              'name': name,
              if (maxspeed != null) 'maxspeed': maxspeed,
              if (oneway != null) 'oneway': oneway,
            }),
          ],
        );

    test('non-oneway → dua edge terarah, keduanya boleh mobil', () {
      final g = buildGraph(data(maxspeed: '40'));
      expect(g.nodeCount, 2);
      final a = g.indexOfOsmId(1)!, b = g.indexOfOsmId(2)!;
      final fromA = g.edgesFrom(a);
      final fromB = g.edgesFrom(b);
      expect(fromA.length, 1);
      expect(fromB.length, 1);
      expect(fromA.first.to, b);
      expect(fromB.first.to, a);
      expect(fromA.first.car, isTrue);
      expect(fromB.first.car, isTrue);
    });

    test('panjang edge ≈ haversine (~111 m untuk 0.001° lat)', () {
      final g = buildGraph(data());
      final e = g.edgesFrom(g.indexOfOsmId(1)!).first;
      expect(e.length, closeTo(111.2, 1.0));
    });

    test('speed dari maxspeed bila ada', () {
      final g = buildGraph(data(maxspeed: '55'));
      expect(g.edgesFrom(g.indexOfOsmId(1)!).first.speed, 55);
    });

    test('speed default per highway bila maxspeed kosong', () {
      final g = buildGraph(data(highway: 'residential'));
      expect(g.edgesFrom(g.indexOfOsmId(1)!).first.speed, 30);
    });

    test('oneway=yes → edge maju boleh mobil, edge balik TIDAK', () {
      final g = buildGraph(data(oneway: 'yes'));
      final fwd = g.edgesFrom(g.indexOfOsmId(1)!).first;
      final bwd = g.edgesFrom(g.indexOfOsmId(2)!).first;
      expect(fwd.car, isTrue);
      expect(bwd.car, isFalse); // mobil tak boleh lawan arah; foot boleh (di A*)
    });

    test('nama jalan tersimpan di edge', () {
      final g = buildGraph(data(name: 'Jl Mangga'));
      expect(g.edgesFrom(g.indexOfOsmId(1)!).first.name, 'Jl Mangga');
    });

    test('node id sama di dua way → persimpangan tersambung', () {
      final d = const OsmData(
        [
          OsmNode(1, 1.0, 100.0),
          const OsmNode(2, 1.001, 100.0),
          const OsmNode(3, 1.001, 100.001),
        ],
        [
          const OsmWay(10, [1, 2], {'highway': 'residential'}),
          const OsmWay(11, [2, 3], {'highway': 'residential'}),
        ],
      );
      final g = buildGraph(d);
      // node 2 punya edge ke 1 dan ke 3 → derajat 2 (persimpangan).
      expect(g.edgesFrom(g.indexOfOsmId(2)!).length, 2);
    });
  });

  test('integrasi: bangun graph dari fixture .pbf nyata', () {
    final bytes = File('test/routing_dart/fixtures/tiny_roads.osm.pbf')
        .readAsBytesSync();
    final g = buildGraph(readOsmPbf(bytes));
    expect(g.nodeCount, 4);
    // way 10 [1,2,3] + way 11 [2,4] → node 2 derajat 3 (ke 1,3,4).
    expect(g.edgesFrom(g.indexOfOsmId(2)!).length, 3);
  });
}
