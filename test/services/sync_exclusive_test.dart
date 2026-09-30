import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/api_service.dart';
import 'package:geoform_app/services/connectivity_service.dart';
import 'package:geoform_app/services/photo_sync_service.dart';
import 'package:geoform_app/services/storage_service.dart';
import 'package:geoform_app/services/sync_service.dart';
import 'package:geoform_app/services/sync_watermark_service.dart';

/// Semua jalur sync yang MENULIS DB berjalan satu per satu lewat
/// [SyncService.runExclusive] — logout menunggunya, dan pull tak lagi bisa
/// menulis data user lama ke DB yang baru dikosongkan.

class _Api implements ApiService {
  int gets = 0;
  int posts = 0;

  /// Bila diisi, GET tertahan sampai gate selesai (pull "sedang berjalan").
  Completer<void>? getGate;

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers,
      Map<String, dynamic>? queryParameters}) async {
    gets++;
    if (getGate != null) await getGate!.future;
    return http.Response(jsonEncode({'data': [], 'total_pages': 1}), 200);
  }

  @override
  Future<http.Response> post(String endpoint,
      {Map<String, String>? headers, dynamic body}) async {
    posts++;
    return http.Response(jsonEncode({'message': 'ok'}), 200);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _Storage implements StorageService {
  Project project = _project(synced: false);
  final List<String> syncedProjects = [];

  @override
  Future<Project?> getProjectById(String projectId) async => project;

  @override
  Future<void> updateProjectSyncStatus(String projectId, bool isSynced,
      {DateTime? syncedAt}) async {
    syncedProjects.add(projectId);
  }

  @override
  Future<List<GeoData>> getUnsyncedGeoData({String? projectId}) async => [];

  @override
  Future<List<Project>> getUnsyncedProjects() async => [];

  @override
  Future<List<Project>> loadProjects() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _Connectivity implements ConnectivityService {
  @override
  Future<bool> checkServerReachable() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Project _project({required bool synced}) => Project(
      id: 'p1',
      name: 'Blocks',
      description: '',
      geometryType: GeometryType.point,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      isSynced: synced,
    );

/// Biarkan microtask & timer 0 ms berjalan.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _Api api;
  late _Storage storage;
  late SyncService sync;

  setUp(() {
    api = _Api();
    storage = _Storage();
    sync = SyncService.forTest(
      apiService: api,
      storageService: storage,
      photoSyncService: PhotoSyncService.forTest(apiService: api),
      connectivity: _Connectivity(),
      watermark: SyncWatermarkService(),
    );
  });

  test('runExclusive bersarang langsung jalan (tak deadlock)', () async {
    final result = await sync
        .runExclusive(() => sync.runExclusive(() async => 42))
        .timeout(const Duration(seconds: 2));
    expect(result, 42);
    expect(sync.isSyncing.value, isFalse);
  });

  test('syncProjectAndData (memanggil syncProject di dalam) tetap selesai',
      () async {
    final result = await sync
        .syncProjectAndData(storage.project)
        .timeout(const Duration(seconds: 2));
    expect(result.projectFailed, isFalse);
    expect(storage.syncedProjects, ['p1']);
  });

  test('pull menunggu sync yang sedang berjalan & menandai isSyncing',
      () async {
    final gate = Completer<void>();
    final upload = sync.runExclusive(() => gate.future);
    api.getGate = Completer<void>();

    final pull = sync.pullGeoDataFromServer('p1');
    await _settle();
    expect(api.gets, 0, reason: 'pull must wait for the running upload');

    gate.complete();
    await upload;
    await _settle();
    expect(api.gets, 1);
    expect(sync.isSyncing.value, isTrue, reason: 'a pull counts as syncing');

    api.getGate!.complete();
    expect((await pull).success, isTrue);
    expect(sync.isSyncing.value, isFalse);
  });

  test('pullProjectsFromServer, syncProject, performTwoWaySync juga menunggu',
      () async {
    for (final start in <Future<Object?> Function()>[
      () => sync.pullProjectsFromServer(),
      () => sync.syncProject(storage.project),
      () => sync.performTwoWaySync(),
    ]) {
      final gate = Completer<void>();
      final holder = sync.runExclusive(() => gate.future);
      final before = api.gets + api.posts;
      final call = start();
      await _settle();
      expect(api.gets + api.posts, before,
          reason: 'must not hit the server while another sync runs');
      gate.complete();
      await holder;
      await call.timeout(const Duration(seconds: 2));
    }
  });

  test(
      'continuation basi setelah body selesai TIDAK dianggap reentrant '
      '(tetap menunggu pemegang kunci berikutnya)', () async {
    final order = <String>[];
    final staleDone = Completer<void>();
    await sync.runExclusive(() async {
      // Terjadwal di zone body ini tapi baru jalan SETELAH body selesai.
      Timer(const Duration(milliseconds: 20), () {
        sync
            .runExclusive(() async => order.add('stale'))
            .whenComplete(staleDone.complete);
      });
    });

    final gate = Completer<void>();
    final holder = sync.runExclusive(() async {
      order.add('holder-start');
      await gate.future;
      order.add('holder-end');
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(order, ['holder-start'], reason: 'stale call must wait');

    gate.complete();
    await holder;
    await staleDone.future.timeout(const Duration(seconds: 2));
    expect(order, ['holder-start', 'holder-end', 'stale']);
  });
}
