import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/app_reset/app_reset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppResetService.reset', () {
    test('menjalankan langkah berurutan; gagal/timeout dicatat, lanjut terus',
        () async {
      final calls = <String>[];
      final service = AppResetService(
        stepTimeout: const Duration(milliseconds: 50),
        steps: [
          AppResetStep('tracking', () async => calls.add('tracking')),
          AppResetStep('auth', () async {
            calls.add('auth');
            throw StateError('offline');
          }),
          AppResetStep('hang', () => Completer<void>().future),
          AppResetStep('files', () async => calls.add('files')),
        ],
      );

      final report = await service.reset();

      expect(calls, ['tracking', 'auth', 'files']);
      expect(report.completed, ['tracking', 'files']);
      expect(report.failed.keys, ['auth', 'hang']);
      expect(report.failed['hang'], isA<TimeoutException>());
      expect(report.success, isFalse);
    });

    test('urutan standar: tracking & auth sebelum DB ditutup, berkas dihapus '
        'sebelum prefs, cache memori terakhir', () {
      final names = standardResetStepNames;
      int at(String n) => names.indexOf(n);
      expect(names, containsAll(
          ['tracking', 'downloads', 'auth', 'databases', 'files', 'preferences',
           'memory']));
      expect(at('tracking'), lessThan(at('databases')));
      expect(at('downloads'), lessThan(at('databases')));
      // Logout auth butuh token & daftar topic FCM di prefs.
      expect(at('auth'), lessThan(at('preferences')));
      expect(at('databases'), lessThan(at('files')));
      expect(at('files'), lessThan(at('preferences')));
      expect(names.last, 'memory');
    });
  });

  group('wipeDirectory', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('wipe'));
    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('hapus semua isi (berkas + subfolder), folder induk tetap ada',
        () async {
      File('${root.path}/a.txt').writeAsStringSync('x');
      Directory('${root.path}/basemaps/p1').createSync(recursive: true);
      File('${root.path}/basemaps/p1/overlay.png').writeAsBytesSync([1]);

      final n = await wipeDirectory(root);

      expect(n, 2);
      expect(root.existsSync(), isTrue);
      expect(root.listSync(), isEmpty);
    });

    test('hanya nama yang cocok bila [only] diberikan', () async {
      for (final f in ['geoform.db', 'geoform.db-journal', 'firebase.db']) {
        File('${root.path}/$f').writeAsStringSync('x');
      }
      Directory('${root.path}/MapTiles').createSync();

      await wipeDirectory(root,
          only: (name) => name.startsWith('geoform.db') || name == 'MapTiles');

      expect(root.listSync().map((e) => e.uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty)), ['firebase.db']);
    });

    test('folder tak ada → 0, tanpa error', () async {
      expect(await wipeDirectory(Directory('${root.path}/tidak-ada')), 0);
    });
  });

  group('resetPreferences', () {
    test('hapus semua kunci kecuali allowlist perangkat (nilai dipulihkan '
        'dengan tipe aslinya)', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'rahasia',
        'user_data': '{"id":1}',
        'basemaps': '[]',
        'geojson_layers_v1': '[]',
        'notification_topic_hotspot': true,
        'app_settings': '{"darkMode":true}',
        'gps_settings': '{"minAccuracy":5}',
        'emlid_host': '192.168.4.1',
        'emlid_port': 9001,
        'location_always_requested': true,
        'pinned_x': ['a', 'b'],
      });
      final prefs = await SharedPreferences.getInstance();

      await resetPreferences(prefs);

      expect(prefs.getKeys(), {
        'app_settings',
        'gps_settings',
        'emlid_host',
        'emlid_port',
        'location_always_requested',
      });
      expect(prefs.getInt('emlid_port'), 9001);
      expect(prefs.getBool('location_always_requested'), isTrue);
      expect(prefs.getString('app_settings'), '{"darkMode":true}');
    });

    test('allowlist tak memuat data user', () {
      for (final k in kResetKeepPrefKeys) {
        expect(k, isNot(anyOf(contains('token'), contains('user'),
            contains('basemap'), contains('geojson'), contains('project'),
            contains('notif'), contains('sync'))));
      }
    });
  });
}
