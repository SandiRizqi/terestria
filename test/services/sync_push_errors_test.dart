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

/// Push membawa versi server (`base_updated_at`), menyimpan versi baru dari
/// respons, dan melaporkan error server (mis. project nonaktif) apa adanya —
/// juga per record (`lastSyncError`) untuk ditampilkan di daftar data.

const _inactiveMessage =
    'Project "Blok A" is not accepting data right now (inactive).';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status);

http.Response _ok({String updatedAt = '2026-09-30T09:00:00.654321Z'}) =>
    _json(200, {
      'success': true,
      'message': 'GeoData updated successfully',
      'data': {'id': 'x', 'updatedAt': updatedAt},
    });

http.Response _inactive() => _json(403, {
      'success': false,
      'error_code': 'project_inactive',
      'message': _inactiveMessage,
    });

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
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _Storage implements StorageService {
  final Map<String, Project> projects = {};
  List<GeoData> unsynced = [];
  bool unchanged = true;
  final List<GeoData> conditionalSaves = [];
  final Map<String, DateTime?> serverVersions = {};
  final Map<String, String?> syncErrors = {};

  @override
  Future<Project?> getProjectById(String projectId) async => projects[projectId];

  @override
  Future<List<Project>> getUnsyncedProjects() async => [];

  @override
  Future<List<GeoData>> getUnsyncedGeoData({String? projectId}) async =>
      unsynced;

  @override
  Future<bool> saveGeoDataIfUnchanged(GeoData geoData,
      {required DateTime expectedUpdatedAt}) async {
    if (unchanged) conditionalSaves.add(geoData);
    return unchanged;
  }

  @override
  Future<void> setGeoDataServerVersion(String id, DateTime? version) async =>
      serverVersions[id] = version;

  @override
  Future<void> setGeoDataSyncError(String id, String? message) async =>
      syncErrors[id] = message;

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

Project _project(String id, String name) => Project(
      id: id,
      name: name,
      description: '',
      geometryType: GeometryType.point,
      formFields: const [],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      isSynced: true,
    );

GeoData _geo(String id, String projectId, {DateTime? serverUpdatedAt}) =>
    GeoData(
      id: id,
      projectId: projectId,
      formData: const {'A': 1},
      points: [
        GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026, 9, 30),
      updatedAt: DateTime.utc(2026, 9, 30, 1),
      serverUpdatedAt: serverUpdatedAt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final blokA = _project('pA', 'Blok A');
  final blokB = _project('pB', 'Blok B');

  SyncService sync(_Api api, _Storage storage) => SyncService.forTest(
        apiService: api,
        storageService: storage,
        photoSyncService: _PhotoSync(),
        connectivity: _Connectivity(),
        watermark: SyncWatermarkService(),
      );

  test('payload membawa base_updated_at dari serverUpdatedAt (tanpa base bila '
      'record belum pernah ada di server)', () async {
    final api = _Api([_ok(), _ok()]);
    final storage = _Storage();
    final s = sync(api, storage);

    await s.syncGeoData(
        _geo('g1', 'pA',
            serverUpdatedAt: DateTime.parse('2026-09-30T08:00:00.123456Z')),
        blokA);
    await s.syncGeoData(_geo('g2', 'pA'), blokA);

    expect(api.bodies[0]['base_updated_at'], '2026-09-30T08:00:00.123456Z');
    expect(api.bodies[1].containsKey('base_updated_at'), isFalse);
    expect(api.bodies[0].containsKey('force'), isFalse);
  });

  test('sukses: versi server dari respons disimpan & error dikosongkan',
      () async {
    final storage = _Storage();
    final result =
        await sync(_Api([_ok()]), storage).syncGeoData(_geo('g1', 'pA'), blokA);

    expect(result.success, isTrue);
    final saved = storage.conditionalSaves.single;
    expect(saved.serverUpdatedAt!.toUtc().toIso8601String(),
        '2026-09-30T09:00:00.654321Z');
    expect(saved.lastSyncError, isNull);
    expect(storage.syncErrors['g1'], isNull);
  });

  test('diedit selama upload: versi server baru tetap dicatat (tanpa itu '
      'push berikutnya jadi konflik palsu)', () async {
    final storage = _Storage()..unchanged = false;
    await sync(_Api([_ok()]), storage).syncGeoData(_geo('g1', 'pA'), blokA);

    expect(storage.serverVersions['g1']!.toUtc().toIso8601String(),
        '2026-09-30T09:00:00.654321Z');
  });

  test('403 project_inactive: pesan server apa adanya & dicatat per record',
      () async {
    final storage = _Storage();
    final result = await sync(_Api([_inactive()]), storage)
        .syncGeoData(_geo('g1', 'pA'), blokA);

    expect(result.success, isFalse);
    expect(result.errorCode, 'project_inactive');
    expect(result.message, _inactiveMessage);
    expect(storage.syncErrors['g1'], _inactiveMessage);
  });

  test('batch satu project nonaktif: sisa record dilewati tanpa request',
      () async {
    final api = _Api([_inactive()]);
    final storage = _Storage();
    final result = await sync(api, storage).syncMultipleGeoData(
        [_geo('g1', 'pA'), _geo('g2', 'pA'), _geo('g3', 'pA')], blokA);

    expect(api.bodies, hasLength(1));
    expect(result.failCount, 3);
    expect(result.errors.toSet(), {_inactiveMessage});
    expect(storage.syncErrors, {
      'g1': _inactiveMessage,
      'g2': _inactiveMessage,
      'g3': _inactiveMessage,
    });
  });

  test('sync semua: project nonaktif dilewati, project lain tetap terkirim',
      () async {
    final api = _Api([_inactive(), _ok()]);
    final storage = _Storage()
      ..projects.addAll({'pA': blokA, 'pB': blokB})
      ..unsynced = [_geo('a1', 'pA'), _geo('a2', 'pA'), _geo('b1', 'pB')];

    final result = await sync(api, storage).syncAllUnsyncedData();

    expect(api.bodies.map((b) => b['id']), ['a1', 'b1']);
    expect(result.geoDataSuccess, 1);
    expect(result.geoDataFail, 2);
    expect(result.errors, everyElement(contains('not accepting data')));
    expect(storage.syncErrors['a2'], _inactiveMessage);
  });
}
