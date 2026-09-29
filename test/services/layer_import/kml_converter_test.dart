import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/layer_import/kml_converter.dart';
import 'package:geoform_app/services/layer_import/layer_importer.dart';

const _kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Kebun</name>
  <Folder><name>Blok</name>
    <Folder>
      <Placemark>
        <name>Blok A1</name>
        <description>Tanam 2019</description>
        <ExtendedData>
          <Data name="luas"><value>25.4</value></Data>
          <SchemaData schemaUrl="#s"><SimpleData name="kode">A1</SimpleData></SchemaData>
        </ExtendedData>
        <Polygon>
          <outerBoundaryIs><LinearRing><coordinates>
            106.0,-6.0,0 106.1,-6.0,0 106.1,-6.1,0 106.0,-6.1,0 106.0,-6.0,0
          </coordinates></LinearRing></outerBoundaryIs>
          <innerBoundaryIs><LinearRing><coordinates>
            106.02,-6.02 106.04,-6.02 106.04,-6.04
          </coordinates></LinearRing></innerBoundaryIs>
        </Polygon>
      </Placemark>
    </Folder>
  </Folder>
  <Placemark><name>Pos</name><Point><coordinates>106.5, -6.5, 10</coordinates></Point></Placemark>
  <Placemark><name>Jalan</name>
    <LineString><coordinates>106.0,-6.0 106.2,-6.2</coordinates></LineString>
  </Placemark>
  <Placemark><name>Dua Blok</name>
    <MultiGeometry>
      <Polygon><outerBoundaryIs><LinearRing><coordinates>
        1,1 2,1 2,2 1,1</coordinates></LinearRing></outerBoundaryIs></Polygon>
      <Polygon><outerBoundaryIs><LinearRing><coordinates>
        3,3 4,3 4,4 3,3</coordinates></LinearRing></outerBoundaryIs></Polygon>
    </MultiGeometry>
  </Placemark>
  <Placemark><name>Campur</name>
    <MultiGeometry>
      <Point><coordinates>1,1</coordinates></Point>
      <LineString><coordinates>1,1 2,2</coordinates></LineString>
    </MultiGeometry>
  </Placemark>
  <Placemark><name>Kosong</name></Placemark>
</Document>
</kml>''';

Map<String, dynamic> _byName(Map<String, dynamic> fc, String name) =>
    (fc['features'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((f) => f['properties']['name'] == name);

void main() {
  group('kmlToGeoJson', () {
    final fc = kmlToGeoJson(_kml);

    test('Placemark di Folder bersarang terbaca; tanpa geometri dilewati', () {
      expect((fc['features'] as List).length, 5);
    });

    test('Polygon berlubang: outer + hole (ring ditutup otomatis)', () {
      final f = _byName(fc, 'Blok A1');
      expect(f['geometry']['type'], 'Polygon');
      final rings = f['geometry']['coordinates'] as List;
      expect(rings.length, 2);
      expect((rings[0] as List).first, [106.0, -6.0]);
      expect((rings[0] as List).length, 5);
      final hole = rings[1] as List;
      expect(hole.length, 4);
      expect(hole.first, hole.last);
    });

    test('properti: name, description, ExtendedData Data & SimpleData', () {
      final p = _byName(fc, 'Blok A1')['properties'];
      expect(p['description'], 'Tanam 2019');
      expect(p['luas'], '25.4');
      expect(p['kode'], 'A1');
    });

    test('Point (spasi setelah koma) & LineString', () {
      expect(_byName(fc, 'Pos')['geometry'], {
        'type': 'Point',
        'coordinates': [106.5, -6.5],
      });
      expect(_byName(fc, 'Jalan')['geometry']['type'], 'LineString');
    });

    test('MultiGeometry seragam → MultiPolygon; campuran → GeometryCollection',
        () {
      final m = _byName(fc, 'Dua Blok')['geometry'];
      expect(m['type'], 'MultiPolygon');
      expect((m['coordinates'] as List).length, 2);
      final c = _byName(fc, 'Campur')['geometry'];
      expect(c['type'], 'GeometryCollection');
      expect((c['geometries'] as List).length, 2);
    });

    test('KML tanpa Placemark bergeometri → LayerImportException', () {
      expect(() => kmlToGeoJson('<kml><Document/></kml>'),
          throwsA(isA<LayerImportException>()));
    });
  });

  group('convertLayerBytes KML/KMZ', () {
    final kmlBytes = Uint8List.fromList(utf8.encode(_kml));

    test('.kml dan .xml ber-root <kml>', () {
      expect(convertLayerBytes('kebun.kml', kmlBytes).featureCount, 5);
      final x = convertLayerBytes('kebun.xml', kmlBytes);
      expect(x.format, LayerFormat.kml);
      expect(x.featureCount, 5);
    });

    test('.kmz: zip berisi doc.kml (+ berkas lain)', () {
      final archive = Archive()
        ..addFile(ArchiveFile('files/icon.png', 3, [1, 2, 3]))
        ..addFile(ArchiveFile('doc.kml', kmlBytes.length, kmlBytes));
      final kmz = Uint8List.fromList(ZipEncoder().encode(archive));
      final r = convertLayerBytes('kebun.kmz', kmz);
      expect(r.format, LayerFormat.kmz);
      expect(r.featureCount, 5);
      expect(r.defaultName, 'kebun');
    });

    test('.kmz tanpa .kml / bukan zip → LayerImportException', () {
      final archive = Archive()..addFile(ArchiveFile('a.txt', 1, [65]));
      final noKml = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(() => convertLayerBytes('x.kmz', noKml),
          throwsA(isA<LayerImportException>()));
      expect(() => convertLayerBytes('x.kmz', kmlBytes),
          throwsA(isA<LayerImportException>()));
    });
  });
}
