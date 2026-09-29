import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/layer_import/gpx_converter.dart';
import 'package:geoform_app/services/layer_import/layer_importer.dart';

const _gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="-6.20" lon="106.80">
    <ele>12.5</ele><time>2026-09-01T01:00:00Z</time>
    <name>Pos A</name><desc>Gerbang</desc>
  </wpt>
  <wpt lat="bukan" lon="106.80"><name>Rusak</name></wpt>
  <trk>
    <name>Patroli</name>
    <trkseg>
      <trkpt lat="-6.20" lon="106.80"><time>2026-09-01T02:00:00Z</time></trkpt>
      <trkpt lat="-6.21" lon="106.81"/>
    </trkseg>
    <trkseg>
      <trkpt lat="-6.30" lon="106.90"/>
      <trkpt lat="-6.31" lon="106.91"/>
      <trkpt lat="-6.32" lon="106.92"/>
    </trkseg>
    <trkseg><trkpt lat="-6.4" lon="106.9"/></trkseg>
  </trk>
  <trk><name>Satu Segmen</name>
    <trkseg><trkpt lat="1" lon="2"/><trkpt lat="3" lon="4"/></trkseg>
  </trk>
  <rte><name>Rute</name>
    <rtept lat="-6.5" lon="107.0"/><rtept lat="-6.6" lon="107.1"/>
  </rte>
</gpx>''';

Map<String, dynamic> _byName(Map<String, dynamic> fc, String name) =>
    (fc['features'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((f) => f['properties']['name'] == name);

void main() {
  group('gpxToGeoJson', () {
    final fc = gpxToGeoJson(_gpx);

    test('waypoint → Point [lon, lat] + properti name/desc/ele/time', () {
      final f = _byName(fc, 'Pos A');
      expect(f['geometry'], {
        'type': 'Point',
        'coordinates': [106.8, -6.2],
      });
      expect(f['properties']['desc'], 'Gerbang');
      expect(f['properties']['ele'], 12.5);
      expect(f['properties']['time'], '2026-09-01T01:00:00Z');
      expect(f['properties']['gpx_type'], 'wpt');
    });

    test('titik dengan koordinat rusak dilewati', () {
      expect((fc['features'] as List).where(
          (f) => (f as Map)['properties']['name'] == 'Rusak'), isEmpty);
    });

    test('track multi-segmen → MultiLineString (segmen <2 titik dibuang)', () {
      final f = _byName(fc, 'Patroli');
      expect(f['geometry']['type'], 'MultiLineString');
      final lines = f['geometry']['coordinates'] as List;
      expect(lines.length, 2);
      expect(lines[0], [
        [106.8, -6.2],
        [106.81, -6.21],
      ]);
      expect((lines[1] as List).length, 3);
      expect(f['properties']['time'], '2026-09-01T02:00:00Z');
      expect(f['properties']['gpx_type'], 'trk');
    });

    test('track 1 segmen → LineString; route → LineString', () {
      expect(_byName(fc, 'Satu Segmen')['geometry'], {
        'type': 'LineString',
        'coordinates': [
          [2.0, 1.0],
          [4.0, 3.0],
        ],
      });
      final r = _byName(fc, 'Rute');
      expect(r['geometry']['type'], 'LineString');
      expect(r['properties']['gpx_type'], 'rte');
    });

    test('GPX tanpa geometri / XML rusak → LayerImportException', () {
      expect(() => gpxToGeoJson('<gpx version="1.1"></gpx>'),
          throwsA(isA<LayerImportException>()));
      expect(() => gpxToGeoJson('<gpx><wpt'),
          throwsA(isA<LayerImportException>()));
    });
  });

  test('convertLayerBytes: .gpx dan .xml ber-root <gpx> terkonversi', () {
    final bytes = Uint8List.fromList(utf8.encode(_gpx));
    final a = convertLayerBytes('patroli.gpx', bytes);
    expect(a.format, LayerFormat.gpx);
    expect(a.defaultName, 'patroli');
    expect(a.featureCount, 4);
    expect(a.geometryType, 'Mixed');
    expect(a.propertyKeys, containsAll(['name', 'gpx_type']));
    expect(convertLayerBytes('patroli.xml', bytes).featureCount, 4);
  });
}
