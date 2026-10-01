import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/export/geo_export.dart';

final _t = DateTime.utc(2026, 9, 29, 3);

GeoPoint _p(double lon, double lat, {double? alt, double? acc}) => GeoPoint(
      latitude: lat,
      longitude: lon,
      altitude: alt,
      accuracy: acc,
      timestamp: _t,
    );

Project _project(GeometryType type, {List<FormFieldModel> fields = const []}) =>
    Project(
      id: 'p1',
      name: 'Blok A',
      description: '',
      geometryType: type,
      formFields: fields,
      createdAt: _t,
      updatedAt: _t,
    );

GeoData _data(String id, List<GeoPoint> points,
        {Map<String, dynamic> form = const {}}) =>
    GeoData(
      id: id,
      projectId: 'p1',
      formData: form,
      points: points,
      createdAt: _t,
      updatedAt: _t,
      collectedBy: 'surveyor',
    );

void main() {
  group('GeoExport.geometryFor', () {
    test('record tanpa titik dilewati (dulu diekspor ke [0,0])', () {
      final e = GeoExport.geoJson(_project(GeometryType.point), [
        _data('ok', [_p(106.8, -6.2)]),
        _data('empty', const []),
      ]);
      expect(e.featureCount, 1);
      expect(e.skippedIds, ['empty']);
      final coords = (e.collection['features'] as List).single['geometry']
          ['coordinates'] as List;
      expect(coords, [106.8, -6.2]);
    });

    test('garis butuh ≥2 posisi berbeda', () {
      expect(GeoExport.geometryFor(GeometryType.line, [_p(1, 1)]), isNull);
      expect(
          GeoExport.geometryFor(GeometryType.line, [_p(1, 1), _p(1, 1)]),
          isNull);
      expect(
          GeoExport.geometryFor(GeometryType.line, [_p(1, 1), _p(2, 1)])!
              ['type'],
          'LineString');
    });

    test('ring poligon ditutup berdasarkan NILAI, tanpa vertex ganda', () {
      // Sudah tertutup (titik terakhir = titik pertama, objek berbeda).
      final g = GeoExport.geometryFor(GeometryType.polygon,
          [_p(0, 0), _p(1, 0), _p(1, 1), _p(0, 1), _p(0, 0)])!;
      final ring = (g['coordinates'] as List).single as List;
      expect(ring.length, 5);
      expect(ring.first, ring.last);

      // Belum tertutup → ditutup satu kali.
      final open = GeoExport.geometryFor(
          GeometryType.polygon, [_p(0, 0), _p(1, 0), _p(1, 1)])!;
      final r2 = (open['coordinates'] as List).single as List;
      expect(r2.length, 4);
      expect(r2.first, r2.last);
    });

    test('poligon < 3 titik berbeda → tidak valid', () {
      expect(
          GeoExport.geometryFor(
              GeometryType.polygon, [_p(0, 0), _p(1, 0), _p(0, 0)]),
          isNull);
    });

    test('ring luar berlawanan jarum jam (RFC 7946)', () {
      // Searah jarum jam → dibalik.
      final g = GeoExport.geometryFor(GeometryType.polygon,
          [_p(0, 0), _p(0, 1), _p(1, 1), _p(1, 0)])!;
      final ring = ((g['coordinates'] as List).single as List)
          .map((c) => (c as List).cast<double>())
          .toList();
      var area = 0.0;
      for (var i = 0; i < ring.length - 1; i++) {
        area += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1];
      }
      expect(area, greaterThan(0));
    });

    test('dimensi seragam: altitude hanya bila semua titik punya', () {
      final mixed = GeoExport.positions(
          [_p(0, 0, alt: 10), _p(1, 0), _p(1, 1, alt: 12)]);
      expect(mixed.every((c) => c.length == 2), isTrue);
      final all = GeoExport.positions(
          [_p(0, 0, alt: 10), _p(1, 0, alt: 11)]);
      expect(all.every((c) => c.length == 3), isTrue);
    });

    test('koordinat NaN / di luar rentang dibuang', () {
      final pos = GeoExport.positions(
          [_p(double.nan, 0), _p(0, 95), _p(106.8, -6.2)]);
      expect(pos, [
        [106.8, -6.2]
      ]);
    });
  });

  group('GeoExport.geoJson', () {
    test('hasil bisa di-encode walau formData berisi NaN/DateTime', () {
      final e = GeoExport.geoJson(_project(GeometryType.point), [
        _data('a', [_p(106.8, -6.2, acc: 3.5)],
            form: {'Luas': double.nan, 'Waktu': DateTime.utc(2026, 1, 2)}),
      ]);
      final decoded = jsonDecode(e.encode()) as Map<String, dynamic>;
      final props = (decoded['features'] as List).single['properties'] as Map;
      expect(props['Luas'], isNull);
      expect(props['Waktu'], '2026-01-02T00:00:00.000Z');
      expect(props['gpsAccuracyM'], 3.5);
      expect(props['collectedBy'], 'surveyor');
      expect(props['createdAt'], endsWith('Z'));
    });
  });

  group('GeoExport.csv', () {
    test('escape, cegah formula, checkbox Yes/No, jumlah foto', () {
      final project = _project(GeometryType.point, fields: [
        FormFieldModel(id: 'n', label: 'Name', type: FieldType.text),
        FormFieldModel(id: 'c', label: 'Done', type: FieldType.checkbox),
        FormFieldModel(id: 'f', label: 'Photo', type: FieldType.photo),
      ]);
      final csv = GeoExport.csv(project, [
        _data('a', [_p(106.8, -6.2)], form: {
          'Name': '=HYPERLINK("x")',
          'Done': 'true',
          'Photo': [{}, {}],
        }),
        _data('b', const [], form: {'Name': 'Blok, "B"', 'Done': false}),
      ]);
      final lines = const LineSplitter().convert(csv);
      expect(lines.first,
          'id,latitude,longitude,altitude,point_count,created_at,collected_by,'
          'Name,Done,Photo_photo_count');
      expect(lines[1], contains('"\'=HYPERLINK(""x"")"'));
      expect(lines[1], contains(',Yes,2'));
      expect(lines[2], contains('"Blok, ""B"""'));
      expect(lines[2], contains(',No,0'));
      // Record tanpa titik: sel koordinat kosong, bukan 0.
      expect(lines[2], startsWith('b,,,,0,'));
    });

    test('created_at ditulis UTC (akhiran Z), seragam dengan GeoJSON', () {
      final local = DateTime(2026, 9, 29, 10); // waktu lokal HP
      final record = GeoData(
        id: 'a',
        projectId: 'p1',
        formData: const {},
        points: [_p(106.8, -6.2)],
        createdAt: local,
        updatedAt: local,
      );
      final csv = GeoExport.csv(_project(GeometryType.point), [record]);
      final row = const LineSplitter().convert(csv)[1].split(',');
      expect(row[5], local.toUtc().toIso8601String());
      expect(row[5], endsWith('Z'));
    });

    test('tipe field baru: nilai apa adanya, nama kolom = label (tanpa satuan)',
        () {
      final project = _project(GeometryType.point, fields: [
        FormFieldModel(id: 'n', label: 'Catatan', type: FieldType.textarea),
        FormFieldModel(
            id: 'h',
            label: 'Hama',
            type: FieldType.multiselect,
            options: const ['Ulat api', 'Tikus']),
        FormFieldModel(id: 'j', label: 'Jam', type: FieldType.time),
        FormFieldModel(id: 'w', label: 'Waktu', type: FieldType.datetime),
        FormFieldModel(id: 'k', label: 'Kondisi', type: FieldType.rating),
        FormFieldModel(
            id: 'd', label: 'Diameter', type: FieldType.decimal, unit: 'cm'),
      ]);
      final form = {
        'Catatan': 'Baris 1\nBaris 2',
        'Hama': 'Ulat api; Tikus',
        'Jam': '07:15',
        'Waktu': '2026-10-01T07:15:00.000',
        'Kondisi': 4,
        'Diameter': 35.5,
      };
      final records = [
        _data('a', [_p(106.8, -6.2)], form: form),
        // Pilihan ganda berupa daftar (data lama/web) → digabung "; ".
        _data('b', [_p(106.8, -6.2)], form: {
          'Hama': ['Ulat api', 'Tikus']
        }),
      ];

      final csv = GeoExport.csv(project, records);
      final header = csv.split('\n').first;
      expect(header, endsWith(',Catatan,Hama,Jam,Waktu,Kondisi,Diameter'));
      expect(
          csv,
          contains(',surveyor,"Baris 1\nBaris 2",Ulat api; Tikus,07:15,'
              '2026-10-01T07:15:00.000,4,35.5\n'));
      expect(csv, contains(',surveyor,,Ulat api; Tikus,,,,\n'));

      final geo = jsonDecode(GeoExport.geoJson(project, records).encode())
          as Map<String, dynamic>;
      final props = (geo['features'] as List).first['properties'] as Map;
      for (final e in form.entries) {
        expect(props[e.key], e.value, reason: e.key);
      }
    });

    test('angka negatif tidak diberi awalan', () {
      expect(GeoExport.csvEscape('-6.25'), '-6.25');
      expect(GeoExport.csvEscape(-6.25), '-6.25');
      expect(GeoExport.csvEscape('-abc'), "'-abc");
    });
  });
}
