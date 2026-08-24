import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_dart/astar.dart';
import 'package:geoform_app/services/routing_dart/graph.dart';
import 'package:geoform_app/services/routing_dart/pbf_reader.dart';
import 'package:geoform_app/services/routing_dart/route_builder.dart';

void main() {
  // 3 node kolinear, jarak antar ~111.2 m, residential (30 km/j).
  RoadGraph lineGraph() => buildGraph(const OsmData(
        [
          OsmNode(1, 1.000, 100.0),
          OsmNode(2, 1.001, 100.0),
          OsmNode(3, 1.002, 100.0),
        ],
        [OsmWay(10, [1, 2, 3], {'highway': 'residential'})],
      ));

  test('rakit points + distance + time (car)', () {
    final g = lineGraph();
    final path =
        aStar(g, g.indexOfOsmId(1)!, g.indexOfOsmId(3)!, RouteProfile.car)!;
    final r = buildRouteResult(g, path, RouteProfile.car);

    expect(r.points.length, 3);
    expect(r.latLngs.length, 3);
    expect(r.points.first.latitude, closeTo(1.000, 1e-6));
    expect(r.points.last.latitude, closeTo(1.002, 1e-6));
    // 2 × 111.2 m ≈ 222.4 m
    expect(r.distance, closeTo(222.4, 5));
    // time = 222.4 m ÷ 30 km/j → ~26.7 s → ~26700 ms
    expect(r.time, closeTo(26688, 3000));
    // instruksi diisi di T6
    expect(r.instructions, isEmpty);
  });

  test('foot lebih lama dari car, jarak sama', () {
    final g = lineGraph();
    final s = g.indexOfOsmId(1)!, e = g.indexOfOsmId(3)!;
    final car =
        buildRouteResult(g, aStar(g, s, e, RouteProfile.car)!, RouteProfile.car);
    final foot = buildRouteResult(
        g, aStar(g, s, e, RouteProfile.foot)!, RouteProfile.foot);
    expect(foot.time, greaterThan(car.time));
    expect(foot.distance, closeTo(car.distance, 1));
  });

  test('integrasi: rute dari fixture .pbf (way 10 = [1,2,3])', () {
    final bytes = File('test/routing_dart/fixtures/tiny_roads.osm.pbf')
        .readAsBytesSync();
    final g = buildGraph(readOsmPbf(bytes));
    final path =
        aStar(g, g.indexOfOsmId(1)!, g.indexOfOsmId(3)!, RouteProfile.car)!;
    final r = buildRouteResult(g, path, RouteProfile.car);
    expect(r.points.length, greaterThanOrEqualTo(2));
    expect(r.distance, greaterThan(0));
    expect(r.time, greaterThan(0));
  });
}
