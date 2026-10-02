import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/project_rules.dart';

/// Aturan akurasi project di HP (SPEC §3.6) — rumus sama dengan server
/// (gis-backend `validation.accuracy_violation`).

final _now = DateTime(2026, 10, 2, 8);

GeoPoint _p(double? accuracy, {DateTime? at}) => GeoPoint(
      latitude: -6.2,
      longitude: 106.8,
      accuracy: accuracy,
      timestamp: at ?? _now,
    );

void main() {
  group('ambil titik (tombol "Add point")', () {
    PointCapture decide({
      bool follow = true,
      GeoPoint? fix,
      GeometryType type = GeometryType.point,
      double? limit = 5,
    }) =>
        decidePointCapture(
          followGps: follow,
          fix: fix,
          geometryType: type,
          minAccuracy: limit,
          now: _now,
        );

    test('mode ikuti + fix memenuhi batas → titik GPS (dengan akurasinya)', () {
      final fix = _p(3.2);
      final d = decide(fix: fix);
      expect(d, isA<GpsPointCapture>());
      expect((d as GpsPointCapture).point.accuracy, 3.2);
    });

    test('point: fix di atas batas → ditolak dengan pesan', () {
      final d = decide(fix: _p(7.4));
      expect(d, isA<RejectedPointCapture>());
      expect((d as RejectedPointCapture).message,
          'Accuracy 7.4 m — this project needs 5 m or better.');
    });

    test('point: batas inklusif', () {
      expect(decide(fix: _p(5)), isA<GpsPointCapture>());
    });

    test('point: tanpa fix, fix basi, atau akurasi tak diketahui → ditolak', () {
      expect((decide(fix: null) as RejectedPointCapture).message,
          'No GPS fix yet — this project needs 5 m or better.');
      final stale = _p(2, at: _now.subtract(const Duration(seconds: 31)));
      expect(decide(fix: stale), isA<RejectedPointCapture>());
      expect((decide(fix: _p(null)) as RejectedPointCapture).message,
          'GPS accuracy unknown — this project needs 5 m or better.');
    });

    test('tanpa mode ikuti → titik manual (lolos aturan)', () {
      expect(decide(follow: false, fix: _p(50)), isA<ManualPointCapture>());
      expect(decide(follow: false, fix: null), isA<ManualPointCapture>());
    });

    test('line/polygon: fix buruk tetap diambil (dinilai lewat rata-rata)', () {
      for (final type in [GeometryType.line, GeometryType.polygon]) {
        expect(decide(type: type, fix: _p(50)), isA<GpsPointCapture>());
        expect(decide(type: type, fix: null), isA<ManualPointCapture>());
      }
    });

    test('project tanpa batas: ikuti → GPS bila ada fix, selain itu manual', () {
      expect(decide(limit: null, fix: _p(50)), isA<GpsPointCapture>());
      expect(decide(limit: null, fix: null), isA<ManualPointCapture>());
    });
  });

  group('akurasi record (sama dengan server)', () {
    test('point: akurasi titiknya; manual (0 / tanpa akurasi) lolos', () {
      final v = accuracyViolation(GeometryType.point, [_p(7.4)], 5)!;
      expect((v.measure, v.value, v.limit), (AccuracyMeasure.point, 7.4, 5.0));
      expect(accuracyViolation(GeometryType.point, [_p(0)], 5), isNull);
      expect(accuracyViolation(GeometryType.point, [_p(null)], 5), isNull);
      expect(accuracyViolation(GeometryType.point, [_p(5)], 5), isNull);
    });

    test('line/polygon: rata-rata titik GPS saja', () {
      final points = [_p(3), _p(0), _p(9), _p(null)];
      expect(averageGpsAccuracy(points), 6);
      final v = accuracyViolation(GeometryType.line, points, 5)!;
      expect((v.measure, v.value), (AccuracyMeasure.average, 6.0));
      expect(accuracyViolation(GeometryType.polygon, [_p(0), _p(null)], 5), isNull);
      expect(averageGpsAccuracy([_p(0)]), isNull);
    });

    test('tanpa batas → tidak dinilai', () {
      expect(accuracyViolation(GeometryType.point, [_p(50)], null), isNull);
    });

    test('pesan', () {
      expect(
          accuracyViolationText(const AccuracyViolation(AccuracyMeasure.point, 7.43, 5)),
          "GPS accuracy 7.4 m is above this project's limit (5 m). Take the "
          'point again with a better GPS fix.');
      expect(
          accuracyViolationText(const AccuracyViolation(AccuracyMeasure.average, 8.4, 5)),
          "Average GPS accuracy 8.4 m is above this project's limit (5 m).");
      expect(
          accuracyViolationText(const AccuracyViolation(AccuracyMeasure.point, 5.04, 5)),
          contains('5.04 m'));
    });
  });

  group('ringkasan akurasi (form, sheet, layar edit, editor)', () {
    test('line/polygon: rata-rata dibanding batas', () {
      final over = accuracySummary(GeometryType.line, [_p(9), _p(7.8), _p(0)], 5)!;
      expect(over.text, 'Average GPS accuracy 8.4 m — project limit 5 m');
      expect(over.over, isTrue);
      final ok = accuracySummary(GeometryType.polygon, [_p(3), _p(4)], 5)!;
      expect(ok.text, 'Average GPS accuracy 3.5 m — project limit 5 m');
      expect(ok.over, isFalse);
    });

    test('point: akurasi titiknya', () {
      expect(accuracySummary(GeometryType.point, [_p(7.4)], 5)!.text,
          'GPS accuracy 7.4 m — project limit 5 m');
    });

    test('tanpa titik GPS atau tanpa batas → tidak ada ringkasan', () {
      expect(accuracySummary(GeometryType.line, [_p(0), _p(null)], 5), isNull);
      expect(accuracySummary(GeometryType.line, [_p(9)], null), isNull);
      expect(accuracySummary(GeometryType.line, const [], 5), isNull);
    });

    test('vertex di atas batas', () {
      expect(isAboveLimit(_p(7), 5), isTrue);
      expect(isAboveLimit(_p(5), 5), isFalse);
      expect(isAboveLimit(_p(0), 5), isFalse);
      expect(isAboveLimit(_p(7), null), isFalse);
    });
  });

  group('kombinasi unik (normalisasi sama dengan server)', () {
    FormFieldModel f(String label, FieldType type) =>
        FormFieldModel(id: label, label: label, type: type);
    final fields = [
      f('WERKS', FieldType.text),
      f('BLOCK_NAME', FieldType.dropdown),
      f('NO_TPH', FieldType.number),
      f('Kondisi', FieldType.rating),
      f('Panen', FieldType.checkbox),
      f('Catatan', FieldType.text),
    ];
    Project project(List<String> unique) => Project(
          id: 'P1',
          name: 'Sensus TPH',
          description: '',
          geometryType: GeometryType.point,
          formFields: fields,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          uniqueFields: unique,
        );
    final key = project(['WERKS', 'BLOCK_NAME', 'NO_TPH']);
    GeoData record(String id, Map<String, dynamic> data) => GeoData(
          id: id,
          projectId: 'P1',
          formData: data,
          points: const [],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );

    test('nilai kunci (kasus yang sama dengan test server)', () {
      expect(uniqueKeyValues(key, {'WERKS': ' a1 ', 'BLOCK_NAME': 'B  07', 'NO_TPH': '12'}),
          ['a1', 'b 07', '12']);
      expect(uniqueKeyValues(key, {'WERKS': 'A1', 'BLOCK_NAME': 'b 07', 'NO_TPH': 12.0}),
          ['a1', 'b 07', '12']);
      expect(
          uniqueKeyValues(project(['Kondisi', 'Panen', 'NO_TPH']),
              {'Kondisi': '4', 'Panen': 'true', 'NO_TPH': 10.5}),
          ['4', 'true', '10.5']);
      expect(uniqueKeyValues(project(['Panen']), {'Panen': false}), ['false']);
      expect(uniqueKeyValues(project(['NO_TPH']), {'NO_TPH': ' Dua  Belas '}),
          ['dua belas']);
      // Koma bukan desimal di server → dibandingkan sebagai teks.
      expect(uniqueKeyValues(project(['NO_TPH']), {'NO_TPH': '10,5'}), ['10,5']);
    });

    test('field kunci kosong atau project tanpa aturan → tidak dicek', () {
      expect(uniqueKeyValues(key, {'WERKS': 'A1', 'NO_TPH': 12}), isNull);
      expect(uniqueKeyValues(key, {'WERKS': 'A1', 'BLOCK_NAME': ' ', 'NO_TPH': 12}), isNull);
      expect(uniqueKeyValues(project(const []), {'WERKS': 'A1'}), isNull);
    });

    test('duplikat dicari di record lokal lain; record sendiri dikecualikan', () {
      final records = [
        record('g1', {'WERKS': 'A1', 'BLOCK_NAME': 'B07', 'NO_TPH': 10}),
        record('g2', {'WERKS': 'A2', 'BLOCK_NAME': 'B07', 'NO_TPH': 10}),
      ];
      final data = {'WERKS': 'a1 ', 'BLOCK_NAME': 'b07', 'NO_TPH': '10.0'};
      expect(findDuplicate(key, data, records)?.id, 'g1');
      expect(findDuplicate(key, data, records, excludeId: 'g1'), isNull);
      expect(findDuplicate(key, {'WERKS': 'A3', 'BLOCK_NAME': 'B07', 'NO_TPH': 10}, records),
          isNull);
      expect(findDuplicate(project(const []), data, records), isNull);
    });

    test('pesan sama dengan server', () {
      expect(duplicateMessage(key, {'WERKS': 'A1 ', 'BLOCK_NAME': 'B07', 'NO_TPH': 12.0}),
          'WERKS=A1, BLOCK_NAME=B07, NO_TPH=12 already exists in this project.');
    });

    test('kunci berubah? (layar edit hanya mengecek bila berubah)', () {
      expect(uniqueKeyChanged(key, {'WERKS': 'A1', 'BLOCK_NAME': 'B07', 'NO_TPH': 12},
          {'WERKS': 'a1', 'BLOCK_NAME': 'B07', 'NO_TPH': '12', 'Catatan': 'x'}), isFalse);
      expect(uniqueKeyChanged(key, {'WERKS': 'A1', 'BLOCK_NAME': 'B07', 'NO_TPH': 12},
          {'WERKS': 'A2', 'BLOCK_NAME': 'B07', 'NO_TPH': 12}), isTrue);
    });
  });

  test('titik manual: akurasi 0 atau tanpa akurasi', () {
    expect(_p(0).isManual, isTrue);
    expect(_p(null).isManual, isTrue);
    expect(_p(2.5).isManual, isFalse);
  });

  test('teks batas project di kartu status GPS', () {
    expect(projectLimitText(5, 3.2), 'Project limit 5 m');
    expect(projectLimitText(5, 7.4), 'Project limit 5 m — current GPS ±7.4 m is not enough');
    expect(projectLimitText(2.5, null), 'Project limit 2.5 m');
  });
}
