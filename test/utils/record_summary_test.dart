import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/settings/app_settings.dart';
import 'package:geoform_app/utils/record_summary.dart';
import 'package:geoform_app/widgets/map/tools/measure_math.dart';
import 'package:latlong2/latlong.dart';

/// Ringkasan satu record untuk tampilan list data project:
/// "<isian kedua> · <luas/panjang> · <pengumpul>, <waktu>".

final _now = DateTime(2026, 10, 8, 14, 30);

Project _project(GeometryType type) => Project(
      id: 'p',
      name: 'Blok C',
      description: '',
      geometryType: type,
      formFields: [
        FormFieldModel(id: 'a', label: 'Plot', type: FieldType.text),
        FormFieldModel(id: 'f', label: 'Foto', type: FieldType.photo),
        FormFieldModel(id: 'b', label: 'Condition', type: FieldType.text),
        FormFieldModel(id: 'c', label: 'Diameter', type: FieldType.decimal, unit: 'cm'),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

GeoPoint _p(double lat, double lon) =>
    GeoPoint(latitude: lat, longitude: lon, timestamp: DateTime(2026));

// Persegi ±100 m × 100 m di ekuator.
final _square = [_p(0, 0), _p(0, 0.0009), _p(0.0009, 0.0009), _p(0.0009, 0)];

GeoData _geo({
  Map<String, dynamic> form = const {'Plot': 'C-34', 'Condition': 'Mature'},
  List<GeoPoint>? points,
  String? collectedBy = 'rizky',
  DateTime? createdAt,
}) =>
    GeoData(
      id: 'g1',
      projectId: 'p',
      formData: form,
      points: points ?? [_p(-6.2, 106.8)],
      createdAt: createdAt ?? DateTime(2026, 10, 8, 10, 42),
      updatedAt: createdAt ?? DateTime(2026, 10, 8, 10, 42),
      collectedBy: collectedBy,
    );

final _ha = AppSettings(areaUnit: AreaUnit.hectares);

void main() {
  group('shortRecordTime', () {
    test('hari ini → jam:menit', () {
      expect(shortRecordTime(DateTime(2026, 10, 8, 9, 5), _now), '09:05');
    });
    test('kemarin → "yesterday"', () {
      expect(shortRecordTime(DateTime(2026, 10, 7, 23, 59), _now), 'yesterday');
    });
    test('tahun yang sama → tanggal + bulan', () {
      expect(shortRecordTime(DateTime(2026, 9, 28, 8), _now), '28 Sep');
    });
    test('tahun lain → tanggal lengkap', () {
      expect(shortRecordTime(DateTime(2025, 12, 31, 8), _now), '31 Dec 2025');
    });
  });

  group('collectorLabel', () {
    test('milik user sendiri (beda huruf besar/spasi) → "you"', () {
      expect(collectorLabel(' Rizky ', 'rizky'), 'you');
    });
    test('milik orang lain → namanya; tanpa pengumpul → null', () {
      expect(collectorLabel('dewi.s', 'rizky'), 'dewi.s');
      expect(collectorLabel(null, 'rizky'), isNull);
      expect(collectorLabel('dewi.s', null), 'dewi.s');
    });
  });

  group('recordMeasureText', () {
    test('polygon → luas dengan unit Settings', () {
      final text = recordMeasureText(
          _geo(points: _square), GeometryType.polygon, _ha);
      final expected = _ha.formatArea(polygonAreaSqMeters(
          _square.map((p) => LatLng(p.latitude, p.longitude)).toList()));
      expect(text, expected);
      expect(text, endsWith('ha'));
    });
    test('line → panjang dengan unit Settings', () {
      final line = [_p(0, 0), _p(0, 0.0009)];
      final text =
          recordMeasureText(_geo(points: line), GeometryType.line, AppSettings());
      expect(text, AppSettings().formatDistance(haversineMeters(0, 0, 0, 0.0009)));
    });
    test('point, atau geometri belum lengkap → null', () {
      expect(recordMeasureText(_geo(), GeometryType.point, _ha), isNull);
      expect(
          recordMeasureText(
              _geo(points: _square.take(2).toList()), GeometryType.polygon, _ha),
          isNull);
      expect(
          recordMeasureText(_geo(points: [_p(0, 0)]), GeometryType.line, _ha),
          isNull);
    });
  });

  group('recordSubtitle', () {
    test('isian kedua · luas · "you, jam"', () {
      final text = recordSubtitle(
        _geo(points: _square),
        _project(GeometryType.polygon),
        currentUsername: 'rizky',
        now: _now,
        settings: _ha,
      );
      expect(text, startsWith('Mature · '));
      expect(text, endsWith(' · you, 10:42'));
      expect(text, contains('ha'));
    });

    test('isian kedua terformat sesuai tipe field; foto dilewati', () {
      final text = recordSubtitle(
        _geo(form: {'Plot': 'C-34', 'Foto': ['/a.jpg'], 'Diameter': 35.5}),
        _project(GeometryType.point),
        currentUsername: 'rizky',
        now: _now,
        settings: _ha,
      );
      expect(text, '35.5 cm · you, 10:42');
    });

    test('tanpa isian kedua & tanpa pengumpul → hanya waktu', () {
      final text = recordSubtitle(
        _geo(form: {'Plot': 'C-34'}, collectedBy: null),
        _project(GeometryType.point),
        currentUsername: 'rizky',
        now: _now,
        settings: _ha,
      );
      expect(text, '10:42');
    });

    test('isian kedua kosong dilewati; isian panjang dipotong', () {
      final long = recordSubtitle(
        _geo(form: {'Plot': 'C-34', 'Condition': 'x' * 50}),
        _project(GeometryType.point),
        currentUsername: null,
        now: _now,
        settings: _ha,
      );
      expect(long, '${'x' * 30}… · rizky, 10:42');

      final empty = recordSubtitle(
        _geo(form: {'Plot': 'C-34', 'Condition': '  '}),
        _project(GeometryType.point),
        currentUsername: null,
        now: _now,
        settings: _ha,
      );
      expect(empty, 'rizky, 10:42');
    });
  });
}
