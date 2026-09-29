import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/layer_import/layer_importer.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

const _fc = '''
{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"blok":"A1","luas":2.5},
  "geometry":{"type":"Polygon","coordinates":[[[106.7,-6.2],[106.8,-6.2],[106.8,-6.1],[106.7,-6.2]]]}},
 {"type":"Feature","properties":{"blok":"A2","kode":"X"},
  "geometry":{"type":"MultiPolygon","coordinates":[[[[106.7,-6.2],[106.8,-6.2],[106.8,-6.1],[106.7,-6.2]]]]}}
]}''';

void main() {
  group('detectLayerFormat', () {
    test('dari ekstensi (tak peka kapital)', () {
      expect(detectLayerFormat('a.geojson', _utf8('{}')), LayerFormat.geojson);
      expect(detectLayerFormat('a.JSON', _utf8('{}')), LayerFormat.geojson);
      expect(detectLayerFormat('a.gpx', _utf8('<gpx/>')), LayerFormat.gpx);
      expect(detectLayerFormat('a.kml', _utf8('<kml/>')), LayerFormat.kml);
      expect(detectLayerFormat('a.kmz', [0x50, 0x4b, 3, 4]), LayerFormat.kmz);
      expect(detectLayerFormat('a.zip', [0x50, 0x4b, 3, 4]),
          LayerFormat.zippedShapefile);
    });

    test('.xml diendus dari elemen root (lewati prolog, komentar, BOM)', () {
      expect(
          detectLayerFormat(
              'track.xml',
              _utf8('﻿<?xml version="1.0"?>\n<!-- <kml> bukan ini -->\n'
                  '<gpx version="1.1" creator="x"></gpx>')),
          LayerFormat.gpx);
      expect(
          detectLayerFormat('batas.xml',
              _utf8('<?xml version="1.0"?><kml:kml xmlns:kml="x"></kml:kml>')),
          LayerFormat.kml);
    });

    test('.xml lain / ekstensi tak dikenal → pesan daftar format', () {
      expect(
          () => detectLayerFormat('a.xml', _utf8('<svg></svg>')),
          throwsA(isA<LayerImportException>().having(
              (e) => e.message, 'message', contains('GPX'))));
      expect(
          () => detectLayerFormat('a.csv', _utf8('x,y')),
          throwsA(isA<LayerImportException>().having((e) => e.message,
              'message', allOf(contains('.geojson'), contains('.zip')))));
    });
  });

  group('convertLayerBytes — GeoJSON', () {
    test('FeatureCollection → tipe, kunci properti, nama default, jumlah', () {
      final r = convertLayerBytes('Blok Kebun.geojson', _utf8(_fc));
      expect(r.format, LayerFormat.geojson);
      expect(r.defaultName, 'Blok Kebun');
      expect(r.geometryType, 'Polygon');
      expect(r.propertyKeys, ['blok', 'kode', 'luas']);
      expect(r.featureCount, 2);
      final decoded = jsonDecode(r.geoJsonText) as Map<String, dynamic>;
      expect(decoded['type'], 'FeatureCollection');
      expect((decoded['features'] as List).length, 2);
    });

    test('Feature tunggal / geometri polos dibungkus jadi FeatureCollection',
        () {
      final f = convertLayerBytes(
          'f.json',
          _utf8('{"type":"Feature","properties":{"n":1},'
              '"geometry":{"type":"Point","coordinates":[106.7,-6.2]}}'));
      expect(f.featureCount, 1);
      expect(f.geometryType, 'Point');
      expect(jsonDecode(f.geoJsonText)['type'], 'FeatureCollection');

      final g = convertLayerBytes('g.json',
          _utf8('{"type":"LineString","coordinates":[[106.7,-6.2],[106.8,-6.1]]}'));
      expect(g.geometryType, 'LineString');
      expect(g.featureCount, 1);
    });

    test('JSON rusak / bukan GeoJSON / tanpa fitur → LayerImportException', () {
      for (final bad in ['{rusak', '[1,2]', '{"a":1}',
          '{"type":"FeatureCollection","features":[]}']) {
        expect(() => convertLayerBytes('x.geojson', _utf8(bad)),
            throwsA(isA<LayerImportException>()),
            reason: bad);
      }
    });
  });

  test('importLayerFile membaca berkas & mengonversi di isolate', () async {
    final dir = await Directory.systemTemp.createTemp('layer_import');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/kebun.geojson')..writeAsStringSync(_fc);

    final r = await importLayerFile(f.path, fileName: 'kebun.geojson');
    expect(r.defaultName, 'kebun');
    expect(r.featureCount, 2);
  });
}
