import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/sync_conflict.dart';
import 'package:geoform_app/services/api_service.dart';
import 'package:geoform_app/services/connectivity_service.dart';
import 'package:geoform_app/services/photo_sync_service.dart';
import 'package:geoform_app/services/storage_service.dart';
import 'package:geoform_app/services/sync_service.dart';
import 'package:geoform_app/services/sync_watermark_service.dart';

/// Konflik editan (D2): server menolak push dengan 409 bila record berubah
/// sejak versi yang terakhir dilihat app. App menyimpan versi server, tidak
/// mengunggahnya ulang otomatis, dan user memilih Keep mine / Use server.

final _t0 = DateTime.parse('2026-09-30T08:00:00.100000Z');
final _t1 = DateTime.parse('2026-09-30T09:30:00.200000Z');

Map<String, dynamic> _serverRecord(String id, DateTime updatedAt,
        {String value = 'server'}) =>
    {
      'id': id,
      'project_id': 'pA',
      'form_data': {'A': value},
      'points': [
        {'latitude': -6.2, 'longitude': 106.8, 'timestamp': '2026-09-30T00:00:00Z'}
      ],
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': updatedAt.toIso8601String(),
      'collected_by': 'rekan',
    };

http.Response _conflict(String id) => http.Response(
    jsonEncode({
      'success': false,
      'error_code': 'conflict',
      'message': 'This record was changed on the server by someone else.',
      'data': _serverRecord(id, _t1),
    }),
    409);

http.Response _ok() => http.Response(
    jsonEncode({
      'success': true,
      'data': {'id': 'x', 'updatedAt': '2026-09-30T10:00:00.300000Z'},
    }),
    200);

http.Response _page(List<Map<String, dynamic>> data) =>
    http.Response(jsonEncode({'data': data, 'total_pages': 1}), 200);

class _Api implements ApiService {
  final List<http.Response> responses;
  final List<Map<String, dynamic>> bodies = [];
  _Api(this.responses);

  @override
  Future<http.Response> post(String endpoint,
      {Map<String, String>? headers, dynamic body}) async {
    bodies.add(Map<String, dynamic>.from(body as Map));
    return responses.removeAt(0);
  }

  @override
  Future<http.Response> get(String endpoint,
          {Map<String, String>? headers,
          Map<String, dynamic>? queryParameters}) async =>
      responses.removeAt(0);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _Storage implements StorageService {
  final Map<String, Project> projects = {};
  final Map<String, GeoData> records = {};
  final Map<String, SyncConflict> conflicts = {};
  final Map<String, String?> syncErrors = {};

  @override
  Future<Project?> getProjectById(String projectId) async => projects[projectId];

  @override
  Future<List<Project>> getUnsyncedProjects() async => [];

  @override
  Future<GeoData?> getGeoDataById(String id) async => records[id];

  @override
  Future<List<GeoData>> getUnsyncedGeoData({String? projectId}) async => [
        for (final g in records.values)
          if (!g.isSynced && (projectId == null || g.projectId == projectId)) g,
      ];

  @override
  Future<void> saveGeoData(GeoData geoData) async =>
      records[geoData.id] = geoData;

  @override
  Future<bool> saveGeoDataIfUnchanged(GeoData geoData,
      {required DateTime expectedUpdatedAt}) async {
    records[geoData.id] = geoData;
    return true;
  }

  @override
  Future<void> setGeoDataServerVersion(String id, DateTime? version) async {}

  @override
  Future<void> setGeoDataSyncError(String id, String? message) async =>
      syncErrors[id] = message;

  @override
  Future<void> saveSyncConflict(SyncConflict conflict) async =>
      conflicts[conflict.geoDataId] = conflict;

  @override
  Future<SyncConflict?> getSyncConflict(String geoDataId) async =>
      conflicts[geoDataId];

  @override
  Future<List<SyncConflict>> getSyncConflicts({String? projectId}) async => [
        for (final c in conflicts.values)
          if (projectId == null || c.projectId == projectId) c,
      ];

  @override
  Future<void> deleteSyncConflict(String geoDataId) async =>
      conflicts.remove(geoDataId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _PhotoSync implements PhotoSyncService {
  @override
  Future<Map<String, dynamic>> processFormDataForPush(
          Map<String, dynamic> formData, Project project) async =>
      formData;

  @override
  Future<Map<String, dynamic>> processFormDataForPull(
          Map<String, dynamic> formData, Project? project) async =>
      formData;

  @override
  List<PendingPhoto> pendingPhotoUploads(
          Map<String, dynamic> formData, Project project) =>
      const [];

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

final _blokA = Project(
  id: 'pA',
  name: 'Blok A',
  description: '',
  geometryType: GeometryType.point,
  formFields: const [],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  isSynced: true,
);

GeoData _local(String id, {DateTime? serverUpdatedAt, bool synced = false}) =>
    GeoData(
      id: id,
      projectId: 'pA',
      formData: const {'A': 'mine'},
      points: [
        GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 30, 9),
      isSynced: synced,
      serverUpdatedAt: serverUpdatedAt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _Storage storage;
  setUp(() => storage = _Storage()..projects['pA'] = _blokA);

  SyncService sync(_Api api) => SyncService.forTest(
        apiService: api,
        storageService: storage,
        photoSyncService: _PhotoSync(),
        connectivity: _Connectivity(),
        watermark: SyncWatermarkService(),
      );

  test('409 conflict → versi server disimpan, record tetap belum tersinkron',
      () async {
    storage.records['g1'] = _local('g1', serverUpdatedAt: _t0);

    final result =
        await sync(_Api([_conflict('g1')])).syncGeoData(storage.records['g1']!, _blokA);

    expect(result.success, isFalse);
    expect(result.isConflict, isTrue);
    expect(result.message, SyncService.conflictMessage);
    final c = storage.conflicts['g1']!;
    expect(c.projectId, 'pA');
    expect(c.serverVersion!.formData, {'A': 'server'});
    expect(c.serverVersion!.collectedBy, 'rekan');
    expect(storage.records['g1']!.isSynced, isFalse);
    expect(storage.syncErrors['g1'], SyncService.conflictMessage);
  });

  test('sync semua & sync per project MELEWATI record berkonflik', () async {
    storage.records['g1'] = _local('g1', serverUpdatedAt: _t0);
    storage.records['g2'] = _local('g2', serverUpdatedAt: _t0);
    storage.conflicts['g1'] = SyncConflict(
        geoDataId: 'g1',
        projectId: 'pA',
        serverJson: _serverRecord('g1', _t1),
        detectedAt: _t1);

    final api = _Api([_ok(), _ok()]);
    final all = await sync(api).syncAllUnsyncedData();
    expect(api.bodies.map((b) => b['id']), ['g2']);
    expect(all.errors, anyElement(contains(SyncService.conflictMessage)));

    storage.records['g2'] = _local('g2', serverUpdatedAt: _t0); // unsynced lagi
    final batch = await sync(api).syncProjectAndData(_blokA);
    expect(api.bodies.map((b) => b['id']), ['g2', 'g2']);
    expect(batch.errors, contains(SyncService.conflictMessage));
  });

  group('pull', () {
    test('server berubah sejak versi yang dilihat & ada editan lokal → konflik',
        () async {
      storage.records['g1'] = _local('g1', serverUpdatedAt: _t0);
      await sync(_Api([_page([_serverRecord('g1', _t1)])]))
          .pullGeoDataFromServer('pA');

      expect(storage.conflicts.keys, ['g1']);
      expect(storage.records['g1']!.formData, {'A': 'mine'},
          reason: 'local edits are never overwritten by a pull');
    });

    test('server belum berubah sejak versi yang dilihat → bukan konflik',
        () async {
      storage.records['g1'] = _local('g1', serverUpdatedAt: _t1);
      await sync(_Api([_page([_serverRecord('g1', _t1)])]))
          .pullGeoDataFromServer('pA');
      expect(storage.conflicts, isEmpty);
    });

    test('record lama tanpa versi server (sebelum v6) → perilaku lama, bukan '
        'konflik', () async {
      storage.records['g1'] = _local('g1');
      await sync(_Api([_page([_serverRecord('g1', _t1)])]))
          .pullGeoDataFromServer('pA');
      expect(storage.conflicts, isEmpty);
    });
  });

  group('resolve', () {
    setUp(() {
      storage.records['g1'] = _local('g1', serverUpdatedAt: _t0);
      storage.conflicts['g1'] = SyncConflict(
          geoDataId: 'g1',
          projectId: 'pA',
          serverJson: _serverRecord('g1', _t1),
          detectedAt: _t1);
    });

    test('Keep mine → push force; sukses → konflik selesai', () async {
      final api = _Api([_ok()]);
      final result = await sync(api).resolveKeepMine('g1');

      expect(result.success, isTrue);
      expect(api.bodies.single['force'], isTrue);
      expect(api.bodies.single['form_data'], {'A': 'mine'});
      expect(storage.conflicts, isEmpty);
      expect(storage.records['g1']!.isSynced, isTrue);
    });

    test('Keep mine gagal (offline) → konflik tetap ada', () async {
      final api = _Api([http.Response('bad gateway', 502)]);
      final result = await sync(api).resolveKeepMine('g1');
      expect(result.success, isFalse);
      expect(storage.conflicts.keys, ['g1']);
    });

    test('Use server version → lokal diganti versi server & tersinkron',
        () async {
      final result = await sync(_Api([])).resolveUseServer('g1');

      expect(result.success, isTrue);
      final g = storage.records['g1']!;
      expect(g.formData, {'A': 'server'});
      expect(g.isSynced, isTrue);
      expect(g.serverUpdatedAt!.isAtSameMomentAs(_t1), isTrue);
      expect(g.lastSyncError, isNull);
      expect(storage.conflicts, isEmpty);
    });
  });
}
