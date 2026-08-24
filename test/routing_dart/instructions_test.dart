import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/route_result.dart';
import 'package:geoform_app/services/routing_dart/astar.dart';
import 'package:geoform_app/services/routing_dart/graph.dart';
import 'package:geoform_app/services/routing_dart/instructions.dart';
import 'package:geoform_app/services/routing_dart/pbf_reader.dart';

void main() {
  test('rute lurus, satu nama → start + finish saja', () {
    final g = buildGraph(const OsmData(
      [
        OsmNode(1, 1.0, 100.000),
        OsmNode(2, 1.0, 100.001),
        OsmNode(3, 1.0, 100.002),
      ],
      [OsmWay(10, [1, 2, 3], {'highway': 'residential', 'name': 'Main St'})],
    ));
    final path = [g.indexOfOsmId(1)!, g.indexOfOsmId(2)!, g.indexOfOsmId(3)!];
    final ins = buildInstructions(g, path, RouteProfile.car);

    expect(ins.length, 2); // continue-start + finish
    expect(ins[0].sign, TurnSign.continueOnStreet);
    expect(ins[0].interval, 0);
    expect(ins[0].text, contains('Main St'));
    expect(ins[0].distance, closeTo(222.4, 5)); // seluruh panjang sebelum finish
    expect(ins.last.sign, TurnSign.finish);
    expect(ins.last.interval, 2);
  });

  test('belok kiri (timur → utara) → sign turnLeft di simpang', () {
    final g = buildGraph(const OsmData(
      [
        OsmNode(1, 1.000, 100.000), // A
        OsmNode(2, 1.000, 100.001), // B (timur A)
        OsmNode(3, 1.001, 100.001), // C (utara B)
      ],
      [
        OsmWay(10, [1, 2], {'highway': 'residential', 'name': 'East Rd'}),
        OsmWay(11, [2, 3], {'highway': 'residential', 'name': 'North Rd'}),
      ],
    ));
    final path = [g.indexOfOsmId(1)!, g.indexOfOsmId(2)!, g.indexOfOsmId(3)!];
    final ins = buildInstructions(g, path, RouteProfile.car);

    expect(ins.length, 3); // start, belok, finish
    expect(ins[1].sign, TurnSign.turnLeft);
    expect(ins[1].interval, 1);
    expect(ins[1].text.toLowerCase(), contains('left'));
    expect(ins[1].text, contains('North Rd'));
    // instruksi pertama hanya menempuh segmen sebelum belok (~111 m)
    expect(ins[0].distance, closeTo(111.2, 3));
    expect(ins.last.sign, TurnSign.finish);
  });

  test('lurus tapi nama jalan ganti → instruksi continue-onto (sign 0)', () {
    final g = buildGraph(const OsmData(
      [
        OsmNode(1, 1.0, 100.000),
        OsmNode(2, 1.0, 100.001),
        OsmNode(3, 1.0, 100.002),
      ],
      [
        OsmWay(10, [1, 2], {'highway': 'residential', 'name': 'First'}),
        OsmWay(11, [2, 3], {'highway': 'residential', 'name': 'Second'}),
      ],
    ));
    final path = [g.indexOfOsmId(1)!, g.indexOfOsmId(2)!, g.indexOfOsmId(3)!];
    final ins = buildInstructions(g, path, RouteProfile.car);
    expect(ins.length, 3);
    expect(ins[1].sign, TurnSign.continueOnStreet);
    expect(ins[1].text, contains('Second'));
  });

  test('path satu titik → hanya finish', () {
    final g = buildGraph(const OsmData(
      [OsmNode(1, 1.0, 100.0), OsmNode(2, 1.0, 100.001)],
      [OsmWay(10, [1, 2], {'highway': 'residential'})],
    ));
    final ins = buildInstructions(g, [g.indexOfOsmId(1)!], RouteProfile.car);
    expect(ins.single.sign, TurnSign.finish);
  });
}
