import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/api_service.dart';
import 'package:geoform_app/services/photo_sync_service.dart';
import 'package:geoform_app/services/storage_service.dart';
import 'package:geoform_app/services/sync_service.dart';
import 'package:geoform_app/services/sync_watermark_service.dart';

class _FakeApi implements ApiService {
  final List<http.Response> pages;
  final List<String> requested = [];
  int _i = 0;

  _FakeApi(this.pages);

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, Map<String, dynamic>? queryParameters}) async {
    requested.add(endpoint);
    return pages[_i++];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeStorage implements StorageService {
  final List<GeoData> saved = [];

  @override
  Future<Project?> getProjectById(String projectId) async => Project(
        id: projectId,
        name: 't',
        description: '',
        geometryType: GeometryType.point,
        formFields: const [],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  @override
  Future<GeoData?> getGeoDataById(String id) async => null; // all new

  @override
  Future<void> saveGeoData(GeoData geoData) async => saved.add(geoData);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakePhotoSync implements PhotoSyncService {
  @override
  Future<Map<String, dynamic>> processFormDataForPull(
    Map<String, dynamic> formData,
    Project? project,
  ) async =>
      formData; // no download

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

http.Response _page(List<Map<String, dynamic>> data, int totalPages,
        {int status = 200}) =>
    http.Response(jsonEncode({'data': data, 'total_pages': totalPages}), status);

Map<String, dynamic> _rec(String id, String updatedAt) => {
      'id': id,
      'project_id': 'p1',
      'form_data': <String, dynamic>{},
      'points': [
        {'latitude': 1.0, 'longitude': 2.0, 'timestamp': '2026-01-01T00:00:00Z'}
      ],
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': updatedAt,
      'is_synced': true,
    };

SyncService _sync(_FakeApi api) => SyncService.forTest(
      apiService: api,
      storageService: _FakeStorage(),
      photoSyncService: _FakePhotoSync(),
      watermark: SyncWatermarkService(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('no watermark → full pull (no updated_after), then stores watermark',
      () async {
    final api = _FakeApi([_page([_rec('g1', '2026-06-21T10:37:01.000Z')], 1)]);

    final result = await _sync(api).pullGeoDataFromServer('p1');

    expect(result.success, isTrue);
    expect(api.requested.single, isNot(contains('updated_after')));
    final wm = await SyncWatermarkService().getLastPull('p1');
    expect(wm!.isAtSameMomentAs(DateTime.utc(2026, 6, 21, 10, 37, 1)), isTrue);
  });

  test('existing watermark → sends updated_after and advances it', () async {
    await SyncWatermarkService().setLastPull('p1', DateTime.utc(2026, 6, 1));
    final api = _FakeApi([_page([_rec('g1', '2026-06-21T10:37:01.000Z')], 1)]);

    final result = await _sync(api).pullGeoDataFromServer('p1');

    expect(result.success, isTrue);
    expect(api.requested.single, contains('updated_after=2026-06-01T00:00:00.000Z'));
    final wm = await SyncWatermarkService().getLastPull('p1');
    expect(wm!.isAtSameMomentAs(DateTime.utc(2026, 6, 21, 10, 37, 1)), isTrue);
  });

  test('page error does not advance the watermark', () async {
    await SyncWatermarkService().setLastPull('p1', DateTime.utc(2026, 6, 1));
    final api = _FakeApi([
      _page([_rec('g1', '2026-06-30T00:00:00.000Z')], 2), // page 1 ok
      _page([], 2, status: 500), // page 2 fails
    ]);

    final result = await _sync(api).pullGeoDataFromServer('p1');

    expect(result.success, isFalse);
    final wm = await SyncWatermarkService().getLastPull('p1');
    expect(wm!.isAtSameMomentAs(DateTime.utc(2026, 6, 1)), isTrue,
        reason: 'watermark must stay at old value after a failed page');
  });
}
