import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/layer_import/dbf_reader.dart';
import 'package:geoform_app/services/layer_import/layer_importer.dart';
import 'package:geoform_app/services/layer_import/shapefile_reader.dart';

import 'shapefile_fixtures.dart';

// Shapefile: ring luar searah jarum jam, lubang berlawanan.
const _outer = [
  [0.0, 0.0], [0.0, 10.0], [10.0, 10.0], [10.0, 0.0], [0.0, 0.0], //
];
const _hole = [
  [2.0, 2.0], [4.0, 2.0], [4.0, 4.0], [2.0, 4.0], [2.0, 2.0], //
];
const _outer2 = [
  [20.0, 20.0], [20.0, 30.0], [30.0, 30.0], [30.0, 20.0], [20.0, 20.0], //
];

List<Map<String, dynamic>> _features(Map<String, dynamic> fc) =>
    (fc['features'] as List).cast<Map<String, dynamic>>();

void main() {
  group('shapefileToGeoJson — geometri', () {
    test('Point, PointZ, PointM → Point XY; Null shape dilewati', () {
      for (final type in [1, 11, 21]) {
        final shp = buildShp(type, [
          pointRecord(106.8, -6.2, type: type),
          nullRecord(),
          pointRecord(107.0, -6.5, type: type),
        ]);
        final f = _features(shapefileToGeoJson(shp: shp));
        expect(f.length, 2, reason: 'type $type');
        expect(f[0]['geometry'], {
          'type': 'Point',
          'coordinates': [106.8, -6.2],
        });
      }
    });

    test('MultiPoint (+Z)', () {
      for (final type in [8, 18]) {
        final shp = buildShp(type, [
          multiPointRecord([
            [1.0, 2.0],
            [3.0, 4.0],
          ], type: type),
        ]);
        expect(_features(shapefileToGeoJson(shp: shp)).single['geometry'], {
          'type': 'MultiPoint',
          'coordinates': [
            [1.0, 2.0],
            [3.0, 4.0],
          ],
        });
      }
    });

    test('PolyLine: 1 part → LineString, >1 → MultiLineString (+Z/M)', () {
      for (final type in [3, 13, 23]) {
        final shp = buildShp(type, [
          partsRecord([
            [
              [0.0, 0.0],
              [1.0, 1.0],
            ],
          ], type: type),
          partsRecord([
            [
              [0.0, 0.0],
              [1.0, 1.0],
            ],
            [
              [5.0, 5.0],
              [6.0, 6.0],
              [7.0, 5.0],
            ],
          ], type: type),
        ]);
        final f = _features(shapefileToGeoJson(shp: shp));
        expect(f[0]['geometry']['type'], 'LineString', reason: 'type $type');
        expect(f[1]['geometry']['type'], 'MultiLineString');
        expect((f[1]['geometry']['coordinates'] as List)[1],
            [
              [5.0, 5.0],
              [6.0, 6.0],
              [7.0, 5.0],
            ]);
      }
    });

    test('Polygon: lubang dikelompokkan ke ring luar berdasar arah putaran',
        () {
      for (final type in [5, 15, 25]) {
        final shp = buildShp(type, [
          partsRecord([_outer, _hole], type: type),
          // Lubang ditulis sebelum ring luarnya + satu pulau terpisah.
          partsRecord([_hole, _outer, _outer2], type: type),
        ]);
        final f = _features(shapefileToGeoJson(shp: shp));

        final single = f[0]['geometry'];
        expect(single['type'], 'Polygon', reason: 'type $type');
        expect(single['coordinates'], [_outer, _hole]);

        final multi = f[1]['geometry'];
        expect(multi['type'], 'MultiPolygon');
        expect(multi['coordinates'], [
          [_outer, _hole],
          [_outer2],
        ]);
      }
    });

    test('semua ring berlawanan jarum jam (penulis salah arah) → tiap ring '
        'jadi polygon sendiri, tidak hilang', () {
      final ccw = _outer.reversed.toList();
      final ccw2 = _outer2.reversed.toList();
      final shp = buildShp(5, [
        partsRecord([ccw, ccw2], type: 5),
      ]);
      final g = _features(shapefileToGeoJson(shp: shp)).single['geometry'];
      expect(g['type'], 'MultiPolygon');
      expect((g['coordinates'] as List).length, 2);
    });

    test('transform diterapkan ke tiap koordinat', () {
      final shp = buildShp(1, [pointRecord(10, 20)]);
      final fc = shapefileToGeoJson(
          shp: shp, transform: (x, y) => [x + 100, y - 1]);
      expect(_features(fc).single['geometry']['coordinates'], [110.0, 19.0]);
    });

    test('bukan shapefile / terpotong → LayerImportException', () {
      expect(() => shapefileToGeoJson(shp: Uint8List(50)),
          throwsA(isA<LayerImportException>()));
      final shp = buildShp(1, [pointRecord(1, 2)]);
      final cut = Uint8List.fromList(shp.sublist(0, shp.length - 6));
      expect(() => shapefileToGeoJson(shp: cut),
          throwsA(isA<LayerImportException>()));
      final bad = Uint8List.fromList(shp)..[3] = 0;
      expect(() => shapefileToGeoJson(shp: bad),
          throwsA(isA<LayerImportException>()));
    });
  });

  group('readDbf', () {
    const fields = [
      DbfField('BLOK', 'C', 10),
      DbfField('LUAS', 'N', 8, 2),
      DbfField('POKOK', 'N', 6),
      DbfField('AKTIF', 'L', 1),
      DbfField('TANAM', 'D', 8),
      DbfField('RASIO', 'F', 10, 3),
    ];

    test('tipe C/N/F/L/D terbaca; kosong → null', () {
      final dbf = buildDbf(fields, [
        ['A1', '25.40', '3200', 'T', '20190315', '0.125'],
        ['', '', '', '?', '', ''],
      ]);
      final rows = readDbf(dbf);
      expect(rows[0], {
        'BLOK': 'A1',
        'LUAS': 25.4,
        'POKOK': 3200,
        'AKTIF': true,
        'TANAM': '2019-03-15',
        'RASIO': 0.125,
      });
      expect(rows[1], {
        'BLOK': '',
        'LUAS': null,
        'POKOK': null,
        'AKTIF': null,
        'TANAM': null,
        'RASIO': null,
      });
    });

    test('record bertanda hapus → null', () {
      final dbf = buildDbf(const [DbfField('N', 'C', 4)], [
        ['a'],
        ['b'],
      ], deleted: {0});
      expect(readDbf(dbf), [
        null,
        {'N': 'b'},
      ]);
    });

    test('encoding: UTF-8 default, .cpg Latin-1/1252, fallback Latin-1', () {
      const f = [DbfField('NAMA', 'C', 12)];
      final utf = buildDbf(f, [
        ['Kebun Ñusa'],
      ]);
      expect(readDbf(utf)[0]!['NAMA'], 'Kebun Ñusa');

      final latin = buildDbf(f, [
        ['Kebun Ñusa'],
      ], encode: latin1.encode);
      expect(readDbf(latin, cpg: '1252')[0]!['NAMA'], 'Kebun Ñusa');
      expect(readDbf(latin, cpg: 'ISO-8859-1')[0]!['NAMA'], 'Kebun Ñusa');
      // Tanpa .cpg & bukan UTF-8 valid → Latin-1, bukan karakter rusak.
      expect(readDbf(latin)[0]!['NAMA'], 'Kebun Ñusa');
    });
  });

  test('shapefileToGeoJson menggabungkan atribut .dbf per record', () {
    final shp = buildShp(1, [
      pointRecord(1, 1),
      nullRecord(),
      pointRecord(2, 2),
      pointRecord(3, 3),
    ]);
    final dbf = buildDbf(const [DbfField('ID', 'N', 4)], [
      ['1'],
      ['2'],
      ['3'],
      ['4'],
    ], deleted: {2});
    final f = _features(shapefileToGeoJson(shp: shp, dbf: dbf));
    // Record 2 null shape, record 3 terhapus di .dbf.
    expect(f.map((e) => e['properties']['ID']), [1, 4]);
    expect(jsonEncode(f), isNot(contains('NaN')));
  });
}
