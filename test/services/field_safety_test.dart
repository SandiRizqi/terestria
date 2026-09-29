import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/collection_draft_service.dart';
import 'package:geoform_app/services/device_health_service.dart';
import 'package:geoform_app/services/geometry_validation.dart';
import 'package:geoform_app/services/location_service_v2.dart';
import 'package:geoform_app/widgets/collection/gps_status_banners.dart';
import 'package:geoform_app/widgets/dynamic_form.dart';

/// Titik pada offset meter (timur, utara) dari titik acuan dekat Jakarta.
GeoPoint _m(double eastM, double northM, {double? accuracy, bool rec = true}) {
  const lat0 = -6.2, lon0 = 106.8;
  const mPerDegLat = 111320.0;
  final mPerDegLon = 111320.0 * 0.99414; // cos(-6.2°)
  return GeoPoint(
    latitude: lat0 + northM / mPerDegLat,
    longitude: lon0 + eastM / mPerDegLon,
    accuracy: accuracy,
    timestamp: DateTime(2026, 9, 29),
    recordable: rec,
  );
}

FormFieldModel _f(String label, FieldType type,
        {bool required = false, int? minPhotos, int? maxPhotos}) =>
    FormFieldModel(
      id: label,
      label: label,
      type: type,
      required: required,
      minPhotos: minPhotos,
      maxPhotos: maxPhotos,
    );

void main() {
  group('geometryWarnings', () {
    test('poligon wajar → tanpa peringatan', () {
      final square = [_m(0, 0), _m(20, 0), _m(20, 20), _m(0, 20)];
      expect(geometryWarnings(GeometryType.polygon, square), isEmpty);
    });

    test('poligon "dasi kupu-kupu" → peringatan tepi berpotongan', () {
      final bowtie = [_m(0, 0), _m(20, 20), _m(20, 0), _m(0, 20)];
      expect(polygonSelfIntersects(bowtie), isTrue);
      expect(geometryWarnings(GeometryType.polygon, bowtie).join(),
          contains('cross'));
    });

    test('luas ≈0 & titik ganda terdeteksi', () {
      final flat = [_m(0, 0), _m(0, 0), _m(0.1, 0), _m(0.2, 0)];
      final w = geometryWarnings(GeometryType.polygon, flat).join(' ');
      expect(w, contains('almost zero'));
      expect(w, contains('duplicate'));
    });

    test('garis < 1 m', () {
      expect(geometryWarnings(GeometryType.line, [_m(0, 0), _m(0.5, 0)]),
          isNotEmpty);
      expect(geometryWarnings(GeometryType.line, [_m(0, 0), _m(50, 0)]),
          isEmpty);
    });
  });

  group('formFieldIssues', () {
    final fields = [
      _f('Name', FieldType.text, required: true),
      _f('Area', FieldType.decimal, required: true),
      _f('Photo', FieldType.photo, required: true, maxPhotos: 2),
      _f('Checked', FieldType.checkbox, required: true),
      _f('Note', FieldType.text),
    ];

    test('decimal wajib yang dikosongkan tetap terdeteksi (dulu lolos)', () {
      final issues = formFieldIssues(fields, {
        'Name': 'A',
        'Area': '',
        'Photo': [{}],
        'Checked': true,
      });
      expect(issues.map((i) => i.field.label), ['Area']);
    });

    test('foto kurang/lebih, checkbox wajib, angka tak valid', () {
      final issues = formFieldIssues(fields, {
        'Name': 'A',
        'Area': 'abc',
        'Photo': [{}, {}, {}],
        'Checked': false,
      });
      expect(issues.map((i) => i.field.label), ['Area', 'Photo', 'Checked']);
    });

    test('semua lengkap → kosong', () {
      expect(
          formFieldIssues(fields, {
            'Name': 'A',
            'Area': 2.5,
            'Photo': [{}],
            'Checked': 'true',
          }),
          isEmpty);
    });
  });

  group('parseLocaleNumber', () {
    test('koma & titik desimal, minus', () {
      expect(parseLocaleNumber('2,5'), 2.5);
      expect(parseLocaleNumber('2.5'), 2.5);
      expect(parseLocaleNumber('-3,25'), -3.25);
      expect(parseLocaleNumber('10'), 10);
    });
    test('bukan angka → null', () {
      expect(parseLocaleNumber(''), isNull);
      expect(parseLocaleNumber('-'), isNull);
      expect(parseLocaleNumber('abc'), isNull);
    });
  });

  group('CollectionDraftService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('simpan → muat → hapus', () async {
      final svc = CollectionDraftService();
      await svc.save('p1',
          points: [_m(1, 2)], formData: {'Name': 'Blok A', 'Area': 2.5});
      final d = await svc.load('p1');
      expect(d, isNotNull);
      expect(d!.points.length, 1);
      expect(d.formData['Name'], 'Blok A');
      await svc.clear('p1');
      expect(await svc.load('p1'), isNull);
    });

    test('draft kosong tidak disimpan', () async {
      final svc = CollectionDraftService();
      await svc.save('p2', points: const [], formData: const {});
      expect(await svc.load('p2'), isNull);
    });
  });

  group('gpsBannersFor', () {
    const connected = EmlidStatus(connected: true, requiredQuality: 'fix');

    test('RTK di bawah syarat → banner merah "not recorded"', () {
      final b = gpsBannersFor(
        usingEmlid: true,
        isTracking: true,
        isPaused: false,
        location: null,
        emlid: const EmlidStatus(
            connected: true,
            belowRequirement: true,
            lastQuality: 'float',
            requiredQuality: 'fix'),
        sinceEmlidData: const Duration(seconds: 1),
        sinceScreenOpen: const Duration(minutes: 1),
      );
      expect(b.single.text, contains('FLOAT'));
      expect(b.single.text, contains('not recorded'));
    });

    test('RTK menyambung ulang & data basi', () {
      expect(
          gpsBannersFor(
            usingEmlid: true,
            isTracking: false,
            isPaused: false,
            location: null,
            emlid: const EmlidStatus(reconnecting: true, reconnectAttempt: 2),
            sinceEmlidData: null,
            sinceScreenOpen: Duration.zero,
          ).single.text,
          contains('reconnecting'));
      expect(
          gpsBannersFor(
            usingEmlid: true,
            isTracking: true,
            isPaused: false,
            location: null,
            emlid: connected,
            sinceEmlidData: const Duration(seconds: 25),
            sinceScreenOpen: Duration.zero,
          ).single.text,
          contains('25 s'));
    });

    test('GPS HP lemah saat tracking → titik ditahan; fix bagus → tanpa banner',
        () {
      List<GpsBanner> phone(GeoPoint p) => gpsBannersFor(
            usingEmlid: false,
            isTracking: true,
            isPaused: false,
            location: p,
            emlid: const EmlidStatus(),
            sinceEmlidData: null,
            sinceScreenOpen: const Duration(minutes: 1),
          );
      expect(phone(_m(0, 0, accuracy: 45, rec: false)).single.text,
          contains('Weak GPS'));
      expect(phone(_m(0, 0, accuracy: 4)), isEmpty);
    });

    test('tracking dijeda → banner jeda', () {
      final b = gpsBannersFor(
        usingEmlid: false,
        isTracking: true,
        isPaused: true,
        location: _m(0, 0, accuracy: 4),
        emlid: const EmlidStatus(),
        sinceEmlidData: null,
        sinceScreenOpen: Duration.zero,
      );
      expect(b.single.text, contains('paused'));
    });
  });

  group('storage & battery helpers', () {
    test('storageLevelFor', () {
      expect(storageLevelFor(null), StorageLevel.unknown);
      expect(storageLevelFor(100 * 1024 * 1024), StorageLevel.critical);
      expect(storageLevelFor(300 * 1024 * 1024), StorageLevel.low);
      expect(storageLevelFor(2 * 1024 * 1024 * 1024), StorageLevel.ok);
    });

    test('panduan baterai per merek', () {
      expect(batteryGuidanceFor('Xiaomi'), contains('Autostart'));
      expect(batteryGuidanceFor('samsung'), contains('Sleeping apps'));
      expect(batteryGuidanceFor(null), contains('Unrestricted'));
    });
  });
}
