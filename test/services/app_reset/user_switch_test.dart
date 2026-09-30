// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/app_reset/app_reset_service.dart';
import 'package:geoform_app/services/auth_service.dart';
import 'package:geoform_app/services/auto_sync_service.dart';
import 'package:geoform_app/services/basemap_service.dart';
import 'package:geoform_app/services/database_service.dart';
import 'package:geoform_app/services/layer_service.dart';
import 'package:geoform_app/services/pinned_values_service.dart';
import 'package:geoform_app/services/sync_watermark_service.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart'
    show databaseFactory, databaseFactorySqflitePlugin;

/// Skenario logout user A → login user B di HP yang sama: setelah reset
/// standar, tak ada data A yang terbaca lewat service app.

class _FakePaths extends PathProviderPlatform {
  final String docs, temp, support;
  _FakePaths(this.docs, this.temp, this.support);
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
  @override
  Future<String?> getTemporaryPath() async => temp;
  @override
  Future<String?> getApplicationSupportPath() async => support;
}

void _touch(String path) =>
    (File(path)..parent.createSync(recursive: true)).writeAsStringSync('x');

List<String> _names(Directory d) => d
    .listSync()
    .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
    .toList()
  ..sort();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root, docs, temp, support, dbs;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('user_switch');
    docs = Directory('${root.path}/docs')..createSync();
    temp = Directory('${root.path}/temp')..createSync();
    support = Directory('${root.path}/support')..createSync();
    dbs = Directory('${root.path}/databases')..createSync();
    PathProviderPlatform.instance =
        _FakePaths(docs.path, temp.path, support.path);
    // VM test desktop tak mendaftarkan factory sqflite; pakai factory plugin
    // agar getDatabasesPath lewat channel yang di-mock di bawah.
    databaseFactory = databaseFactorySqflitePlugin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'),
            (call) async {
      if (call.method == 'getDatabasesPath') return dbs.path;
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.tekartik.sqflite'), null);
    await root.delete(recursive: true);
  });

  test('setelah reset, user B tak melihat data user A', () async {
    // ── Data user A ──
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-A',
      'user_data': '{"id":7,"username":"userA"}',
      'is_logged_in': true,
      'basemaps': '[{"id":"pdf-a","name":"Project A · NDVI","type":"pdf",'
          '"urlTemplate":"overlay://pdf-a"}]',
      'selected_basemap': 'pdf-a',
      'geojson_layers_v1': [
        '{"id":"l1","name":"Blok A","filePath":"${docs.path}/geojson_layers/l1.geojson",'
            '"geometryType":"Polygon","isActive":true,'
            '"createdAt":"2026-09-01T00:00:00.000"}'
      ],
      'last_pull_p1': DateTime(2026, 9, 1).toIso8601String(),
      'pinned_p1': '{"Blok":"A1"}',
      'notif_last_sync': '2026-09-01',
      'fcm_subscribed_scopes': '[1,2]',
      // Setelan perangkat.
      'app_settings': '{"darkMode":true}',
      'gps_settings': '{"minAccuracy":5}',
      'emlid_host': '192.168.4.1',
      'device_id': 'dev-1',
    });
    _touch('${docs.path}/geojson_layers/l1.geojson');
    _touch('${docs.path}/basemaps/pdf-a/overlay.png');
    _touch('${docs.path}/photos/p1/foto.jpg');
    _touch('${docs.path}/logs/app-20260901.log');
    _touch('${docs.path}/roads/12.pbf');
    _touch('${temp.path}/analysis/a.pdf');
    _touch('${dbs.path}/geoform.db');
    _touch('${dbs.path}/geoform.db-journal');
    _touch('${dbs.path}/com.google.android.datatransport.events');
    _touch('${support.path}/MapTiles/tiles_pdf-a.db');
    _touch('${support.path}/gh-graph-cache-v2/nodes');
    _touch('${support.path}/PersistedInstallation.json');
    TrackingSessionManager.instance.start(Project(
      id: 'p1',
      name: 'Project A',
      description: '',
      geometryType: GeometryType.line,
      formFields: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ));

    AutoSyncService.instance.lastRun.value =
        AutoSyncRun(at: DateTime(2026, 9, 1), ok: false, summary: 'A failed');

    // ── Logout A ──
    final report = await AppResetService().reset();

    // Di test tak ada Firebase & plugin native: hanya langkah yang bergantung
    // padanya yang boleh gagal (bagian lokal langkah itu tetap jalan).
    expect(report.failed.keys.toSet().difference({'location', 'accounts'}),
        isEmpty,
        reason: '${report.failed}');

    // ── User B membuka app ──
    final auth = AuthService();
    expect(await auth.isLoggedIn(), isFalse);
    expect(await auth.getToken(), isNull);
    expect(await auth.getUser(), isNull);
    expect(await LayerService().loadLayers(), isEmpty);
    expect((await BasemapService().getBasemaps()).map((b) => b.id),
        isNot(contains('pdf-a')));
    expect(await SyncWatermarkService().getLastPull('p1'), isNull);
    expect(await PinnedValuesService().loadPinnedValues('p1'), isEmpty);
    expect(TrackingSessionManager.instance.activeCount, 0);
    expect(AutoSyncService.instance.lastRun.value, isNull,
        reason: "user A's auto-sync status must not be shown to user B");

    // Berkas: Documents & Temp kosong; di folder bersama hanya milik app.
    expect(docs.listSync(), isEmpty);
    expect(temp.listSync(), isEmpty);
    expect(_names(dbs), ['com.google.android.datatransport.events']);
    expect(_names(support), ['PersistedInstallation.json']);

    // DB tak terkunci lagi → user B bisa memakai app.
    expect(DatabaseService.isLockedForReset, isFalse);

    // Setelan perangkat bertahan.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(),
        {'app_settings', 'gps_settings', 'emlid_host', 'device_id'});
  });
}
