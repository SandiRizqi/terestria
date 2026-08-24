import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_dart/pbf_reader.dart';

/// Fixture .osm.pbf dibuat oleh test/routing_dart/fixtures/generate_fixture.py
/// dengan writer osmium yang SAMA dgn roads_osm_builder.write_pbf.
/// Node (lon,lat): 1(100.000,1.000) 2(100.001,1.001) 3(100.002,1.000) 4(100.003,1.001)
/// Way 10: [1,2,3] {highway:residential, name:'Jl Test', maxspeed:40, oneway:no}
/// Way 11: [2,4]   {highway:secondary, name:'Jl Dua'}
void main() {
  final bytes = File('test/routing_dart/fixtures/tiny_roads.osm.pbf')
      .readAsBytesSync();

  test('parse node + koordinat (dense nodes, granularity 100)', () {
    final data = readOsmPbf(bytes);
    expect(data.nodes.length, 4);
    final byId = {for (final n in data.nodes) n.id: n};
    expect(byId[1]!.lat, closeTo(1.000, 1e-6));
    expect(byId[1]!.lon, closeTo(100.000, 1e-6));
    expect(byId[2]!.lat, closeTo(1.001, 1e-6));
    expect(byId[2]!.lon, closeTo(100.001, 1e-6));
    expect(byId[3]!.lat, closeTo(1.000, 1e-6));
    expect(byId[3]!.lon, closeTo(100.002, 1e-6));
    expect(byId[4]!.lat, closeTo(1.001, 1e-6));
    expect(byId[4]!.lon, closeTo(100.003, 1e-6));
  });

  test('parse way: refs (delta) + tag (stringtable)', () {
    final data = readOsmPbf(bytes);
    expect(data.ways.length, 2);
    final w = {for (final x in data.ways) x.id: x};
    expect(w[10]!.refs, [1, 2, 3]);
    expect(w[10]!.tags['highway'], 'residential');
    expect(w[10]!.tags['name'], 'Jl Test');
    expect(w[10]!.tags['maxspeed'], '40');
    expect(w[10]!.tags['oneway'], 'no');
    expect(w[11]!.refs, [2, 4]);
    expect(w[11]!.tags['highway'], 'secondary');
    expect(w[11]!.tags['name'], 'Jl Dua');
  });

  test('byte rusak → OsmPbfException, bukan crash', () {
    expect(() => readOsmPbf(Uint8List.fromList([0, 0, 0, 99])),
        throwsA(isA<OsmPbfException>()));
  });

  test('byte kosong → OsmData kosong', () {
    final data = readOsmPbf(Uint8List(0));
    expect(data.nodes, isEmpty);
    expect(data.ways, isEmpty);
  });
}
