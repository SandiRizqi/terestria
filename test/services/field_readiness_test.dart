import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/services/location_service_v2.dart';
import 'package:geoform_app/services/readiness/field_readiness.dart';
import 'package:geoform_app/widgets/readiness/daily_readiness_check.dart';

final _now = DateTime(2026, 9, 29, 8);

ReadinessInputs _inputs({
  bool android = true,
  bool ios = false,
  bool? serviceOn = true,
  LocationAccess access = LocationAccess.whileInUse,
  bool? battery = true,
  bool? notifications = true,
  int? free = 4 * 1024 * 1024 * 1024,
  GeoPoint? fix,
  bool gpsTested = true,
  bool emlid = false,
  EmlidStatus? emlidStatus,
  OfflineCoverage offline = OfflineCoverage.available,
  int unsynced = 0,
  int photos = 0,
  int sessions = 0,
}) =>
    ReadinessInputs(
      isAndroid: android,
      isIOS: ios,
      now: _now,
      locationServiceOn: serviceOn,
      locationAccess: access,
      ignoringBatteryOptimizations: battery,
      notificationsAllowed: notifications,
      manufacturer: 'Xiaomi',
      freeBytes: free,
      lastFix: fix,
      gpsTested: gpsTested,
      usingEmlid: emlid,
      emlid: emlidStatus,
      basemapName: 'OSM',
      offline: offline,
      unsyncedRecords: unsynced,
      pendingPhotos: photos,
      unsavedSessions: sessions,
    );

GeoPoint _fix({double acc = 4, Duration age = const Duration(seconds: 3)}) =>
    GeoPoint(
        latitude: -6.2,
        longitude: 106.8,
        accuracy: acc,
        timestamp: _now.subtract(age));

ReadinessItem _item(List<ReadinessItem> items, String id) =>
    items.firstWhere((i) => i.id == id);

void main() {
  test('semua baik → tanpa masalah/peringatan (Android, izin saat dipakai)',
      () {
    final items = evaluateReadiness(_inputs(fix: _fix()));
    final c = readinessCounts(items);
    expect(c.problems, 0);
    expect(c.warnings, 0);
    expect(_item(items, 'location_permission').level, ReadinessLevel.ok);
    expect(_item(items, 'gps_fix').detail, contains('±4.0 m'));
    expect(_item(items, 'keep_app').detail, contains('Swiping'));
  });

  test('izin ditolak permanen & GPS mati → masalah dengan tombol perbaikan',
      () {
    final items = evaluateReadiness(_inputs(
        access: LocationAccess.deniedForever, serviceOn: false));
    final perm = _item(items, 'location_permission');
    expect(perm.level, ReadinessLevel.problem);
    expect(perm.fix, ReadinessFix.openAppSettings);
    final gps = _item(items, 'location_service');
    expect(gps.fix, ReadinessFix.openLocationSettings);
    // Tanpa izin, fix GPS tak diuji.
    expect(items.where((i) => i.id == 'gps_fix'), isEmpty);
  });

  test('iOS "While Using" → peringatan; Android → ok', () {
    expect(
        _item(evaluateReadiness(_inputs(android: false, ios: true)),
                'location_permission')
            .level,
        ReadinessLevel.warning);
  });

  test('optimasi baterai aktif → peringatan + panduan merek', () {
    final b = _item(evaluateReadiness(_inputs(battery: false)), 'battery');
    expect(b.level, ReadinessLevel.warning);
    expect(b.fix, ReadinessFix.openBatterySettings);
    expect(b.help, contains('Autostart'));
  });

  test('fix lemah/basi → peringatan; belum ada fix → uji lagi', () {
    expect(_item(evaluateReadiness(_inputs(fix: _fix(acc: 45))), 'gps_fix')
        .level, ReadinessLevel.warning);
    expect(
        _item(evaluateReadiness(
                _inputs(fix: _fix(age: const Duration(minutes: 5)))),
                'gps_fix')
            .detail,
        contains('old'));
    final none = _item(evaluateReadiness(_inputs()), 'gps_fix');
    expect(none.fix, ReadinessFix.retestGps);
  });

  test('penyimpanan kritis, peta offline belum ada, data tertunda', () {
    final items = evaluateReadiness(_inputs(
      free: 100 * 1024 * 1024,
      offline: OfflineCoverage.missing,
      unsynced: 12,
      photos: 30,
      sessions: 1,
    ));
    expect(_item(items, 'storage').level, ReadinessLevel.problem);
    expect(_item(items, 'offline_map').fix, ReadinessFix.openBasemaps);
    expect(_item(items, 'pending_sync').detail,
        startsWith('12 records and 30 photos'));
    expect(_item(items, 'unsaved_sessions').level, ReadinessLevel.warning);
  });

  test('Emlid: terputus → masalah; FLOAT di bawah syarat → peringatan', () {
    expect(
        _item(evaluateReadiness(_inputs(emlid: true)), 'emlid').level,
        ReadinessLevel.problem);
    final below = _item(
        evaluateReadiness(_inputs(
            emlid: true,
            emlidStatus: const EmlidStatus(
                connected: true,
                belowRequirement: true,
                lastQuality: 'float',
                requiredQuality: 'fix'))),
        'emlid');
    expect(below.level, ReadinessLevel.warning);
    expect(below.detail, contains('NOT'));
  });

  test('startBlockingItems hanya butir yang bisa menghentikan tracking', () {
    final items = evaluateReadiness(_inputs(
      battery: false,
      free: 100 * 1024 * 1024,
      unsynced: 3,
    ));
    expect(startBlockingItems(items).map((i) => i.id), ['battery']);
  });

  group('ringkasan beranda (tanpa uji GPS di beranda)', () {
    // Cek cepat beranda: GPS tidak diuji, belum ada fix.
    ReadinessInputs quick({
      OfflineCoverage offline = OfflineCoverage.noLocation,
      int unsynced = 0,
      bool? battery = true,
      LocationAccess access = LocationAccess.whileInUse,
    }) =>
        _inputs(
            gpsTested: false,
            offline: offline,
            unsynced: unsynced,
            battery: battery,
            access: access);

    GpsTestResult lastTest({double acc = 4, Duration ago = const Duration(minutes: 5)}) {
      final at = _now.subtract(ago);
      return gpsTestResultOf(ReadinessInputs(
        isAndroid: true,
        isIOS: false,
        now: at,
        locationServiceOn: true,
        locationAccess: LocationAccess.whileInUse,
        lastFix: GeoPoint(
            latitude: -6.2, longitude: 106.8, accuracy: acc, timestamp: at),
        gpsTested: true,
      ))!;
    }

    test('GPS belum diuji → jujur: "No problems found", ketuk untuk uji', () {
      final s = homeReadinessSummary(quick());
      expect(s.level, ReadinessLevel.ok);
      expect(s.gpsTested, isFalse);
      expect(s.title, 'No problems found');
      expect(s.subtitle, 'Tap to test GPS signal');
    });

    test('uji GPS lengkap terakhir lolos & masih berlaku → "Ready for the field"',
        () {
      final s = homeReadinessSummary(quick(), lastGpsTest: lastTest());
      expect(s.gpsTested, isTrue);
      expect(s.title, 'Ready for the field');
    });

    test('uji GPS sudah lewat masa berlaku → kembali "No problems found"', () {
      final s = homeReadinessSummary(quick(),
          lastGpsTest: lastTest(ago: readinessHomeMaxAge + const Duration(minutes: 1)));
      expect(s.gpsTested, isFalse);
      expect(s.title, 'No problems found');
    });

    test('hasil uji GPS yang lemah ikut dihitung di beranda', () {
      final s = homeReadinessSummary(quick(), lastGpsTest: lastTest(acc: 15));
      expect(s.level, ReadinessLevel.warning);
      expect(s.title, '1 item needs attention');
      expect(s.subtitle, 'GPS signal');
    });

    test('peta offline belum diunduh (dari posisi yang ada) → perlu perhatian',
        () {
      final s = homeReadinessSummary(quick(offline: OfflineCoverage.missing));
      expect(s.level, ReadinessLevel.warning);
      expect(s.title, '1 item needs attention');
      expect(s.subtitle, 'Offline map');
    });

    test('data belum sync punya kartu sendiri, tidak dihitung di sini', () {
      final s = homeReadinessSummary(quick(unsynced: 5), lastGpsTest: lastTest());
      expect(s.title, 'Ready for the field');
    });

    test('masalah tetap merah walau GPS belum diuji', () {
      final s = homeReadinessSummary(
          quick(access: LocationAccess.deniedForever, battery: false));
      expect(s.level, ReadinessLevel.problem);
      expect(s.title, '1 problem before the field');
      expect(s.subtitle, 'Location access · Battery optimization');
    });

    test('hasil uji GPS hanya ada bila GPS benar-benar diuji', () {
      expect(gpsTestResultOf(_inputs(gpsTested: false, fix: _fix())), isNull);
      final r = gpsTestResultOf(_inputs(fix: _fix()))!;
      expect(r.at, _now);
      expect(r.item.id, 'gps_fix');
      expect(r.fix?.accuracy, 4);
      // Diuji tapi tak dapat fix → tetap tercatat (peringatan).
      final none = gpsTestResultOf(_inputs())!;
      expect(none.item.level, ReadinessLevel.warning);
      expect(none.fix, isNull);
    });

    test('posisi untuk cek peta: yang terbaru dan masih berlaku', () {
      final old = _fix(age: readinessHomeMaxAge + const Duration(seconds: 1));
      final mid = _fix(age: const Duration(minutes: 10));
      final fresh = _fix(age: const Duration(minutes: 1));
      expect(freshestFix([mid, null, fresh], _now, readinessHomeMaxAge), fresh);
      expect(freshestFix([old, null], _now, readinessHomeMaxAge), isNull);
      expect(freshestFix(const [], _now, readinessHomeMaxAge), isNull);
    });
  });

  test('tileForLatLon', () {
    // Monas, Jakarta pada zoom 15.
    final t = tileForLatLon(-6.1754, 106.8272, 15);
    expect(t.x, 26107);
    expect(t.y, 16947);
    expect(tileForLatLon(0, 0, 0), (x: 0, y: 0));
  });
}
