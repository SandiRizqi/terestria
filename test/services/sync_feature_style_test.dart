import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/feature_style.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/sync_conflict.dart';
import 'package:geoform_app/services/api_service.dart';
import 'package:geoform_app/services/connectivity_service.dart';
import 'package:geoform_app/services/photo_sync_service.dart';
import 'package:geoform_app/services/storage_service.dart';
import 'package:geoform_app/services/sync_service.dart';
import 'package:geoform_app/services/sync_watermark_service.dart';

/// Style per feature ikut sync (SPEC §3):
/// - push SELALU mengirim key `style` (objek, atau null = default);
/// - pull: objek → dipakai, null → dihapus, key tidak ada (backend lama) →
///   style lokal dipertahankan; "Use server version" mengikuti aturan sama.

const _mine = LayerStyle(
  fillColor: Color(0xFF2196F3),
  fillOpacity: 1.0,
  strokeColor: Color(0xFF2196F3),
  strokeWidth: 3,
  pointSize: 12,
);
const _theirs = LayerStyle(
  fillColor: Color(0xFFFF9800),
  fillOpacity: 0.3,
  strokeColor: Color(0xFFE65100),
  strokeWidth: 2,
  pointSize: 16,
);

final _t0 = DateTime.parse('2026-09-30T08:00:00.100000Z');
final _t1 = DateTime.parse('2026-09-30T09:30:00.200000Z');

Map<String, dynamic> _serverRecord(String id,
        {Object? style, bool withStyleKey = true}) =>
    {
      'id': id,
      'project_id': 'pA',
      'form_data': {'A': 'server'},
      'points': [
        {'latitude': -6.2, 'longitude': 106.8, 'timestamp': '2026-09-30T00:00:00Z'}
      ],
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': _t1.toIso8601String(),
      if (withStyleKey) 'style': style,
    };

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

  @override
  Future<Project?> getProjectById(String projectId) async => projects[projectId];

  @override
  Future<GeoData?> getGeoDataById(String id) async => records[id];

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
  Future<void> setGeoDataSyncError(String id, String? message) async {}

  @override
  Future<SyncConflict?> getSyncConflict(String geoDataId) async =>
      conflicts[geoDataId];

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

GeoData _local(String id, {LayerStyle? style, bool synced = true}) => GeoData(
      id: id,
      projectId: 'pA',
      formData: const {'A': 'mine'},
      points: [
        GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: _t0,
      isSynced: synced,
      serverUpdatedAt: _t0,
      style: style,
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

  group('push', () {
    test('record ber-style → payload berisi style (format kontrak)', () async {
      final api = _Api([_ok()]);
      final geo = _local('g1', style: _mine, synced: false);
      storage.records['g1'] = geo;
      await sync(api).syncGeoData(geo, _blokA);
      expect(api.bodies.single['style'], featureStyleToJson(_mine));
    });

    test('record default → key style tetap dikirim sebagai null (reset di '
        'server)', () async {
      final api = _Api([_ok()]);
      final geo = _local('g1', synced: false);
      storage.records['g1'] = geo;
      await sync(api).syncGeoData(geo, _blokA);
      expect(api.bodies.single.containsKey('style'), isTrue);
      expect(api.bodies.single['style'], isNull);
    });
  });

  group('pull', () {
    test('record baru dari server membawa style-nya', () async {
      await sync(_Api([
        _page([_serverRecord('g1', style: featureStyleToJson(_theirs))])
      ])).pullGeoDataFromServer('pA');
      expect(storage.records['g1']!.style, _theirs);
    });

    test('versi server lebih baru: style objek menggantikan milik lokal',
        () async {
      storage.records['g1'] = _local('g1', style: _mine);
      await sync(_Api([
        _page([_serverRecord('g1', style: featureStyleToJson(_theirs))])
      ])).pullGeoDataFromServer('pA');
      expect(storage.records['g1']!.formData, {'A': 'server'});
      expect(storage.records['g1']!.style, _theirs);
    });

    test('versi server lebih baru dengan style null → style lokal dihapus',
        () async {
      storage.records['g1'] = _local('g1', style: _mine);
      await sync(_Api([
        _page([_serverRecord('g1', style: null)])
      ])).pullGeoDataFromServer('pA');
      expect(storage.records['g1']!.style, isNull);
    });

    test('backend lama (tanpa key style) → style lokal dipertahankan',
        () async {
      storage.records['g1'] = _local('g1', style: _mine);
      await sync(_Api([
        _page([_serverRecord('g1', withStyleKey: false)])
      ])).pullGeoDataFromServer('pA');
      expect(storage.records['g1']!.formData, {'A': 'server'});
      expect(storage.records['g1']!.style, _mine);
    });
  });

  group('konflik: Use server version', () {
    SyncConflict conflict(Map<String, dynamic> serverJson) => SyncConflict(
        geoDataId: 'g1',
        projectId: 'pA',
        serverJson: serverJson,
        detectedAt: _t1);

    test('style versi server ikut diterapkan', () async {
      storage.records['g1'] = _local('g1', style: _mine, synced: false);
      storage.conflicts['g1'] =
          conflict(_serverRecord('g1', style: featureStyleToJson(_theirs)));
      final result = await sync(_Api([])).resolveUseServer('g1');
      expect(result.success, isTrue);
      expect(storage.records['g1']!.style, _theirs);
    });

    test('versi server tanpa key style → style lokal dipertahankan', () async {
      storage.records['g1'] = _local('g1', style: _mine, synced: false);
      storage.conflicts['g1'] =
          conflict(_serverRecord('g1', withStyleKey: false));
      await sync(_Api([])).resolveUseServer('g1');
      expect(storage.records['g1']!.style, _mine);
    });
  });
}
