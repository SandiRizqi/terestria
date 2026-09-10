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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStorage implements StorageService {
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
  Future<GeoData?> getGeoDataById(String id) async => null;

  @override
  Future<void> saveGeoData(GeoData geoData) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePhotoSync implements PhotoSyncService {
  @override
  Future<Map<String, dynamic>> processFormDataForPull(
          Map<String, dynamic> formData, Project? project) async =>
      formData;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response _dataPage(int totalPages) => http.Response(
    jsonEncode({'data': <Map<String, dynamic>>[], 'total_pages': totalPages}), 200);

http.Response _countPage(int n, {int status = 200}) =>
    http.Response(jsonEncode({'total_count': n}), status);

SyncService _sync(_FakeApi api) => SyncService.forTest(
      apiService: api,
      storageService: _FakeStorage(),
      photoSyncService: _FakePhotoSync(),
      watermark: SyncWatermarkService(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pull with formDataFilters appends f=key:value to the request', () async {
    final api = _FakeApi([_dataPage(1)]);

    await _sync(api).pullGeoDataFromServer('p1',
        formDataFilters: {'AFD_NAME': 'E32', 'WERKS': '5421'});

    expect(api.requested.single, contains('f=AFD_NAME:E32'));
    expect(api.requested.single, contains('f=WERKS:5421'));
  });

  test('pull without filters sends no f= (regression)', () async {
    final api = _FakeApi([_dataPage(1)]);
    await _sync(api).pullGeoDataFromServer('p1');
    expect(api.requested.single, isNot(contains('&f=')));
  });

  test('countGeoDataOnServer returns total_count and sends count_only + f=',
      () async {
    final api = _FakeApi([_countPage(7)]);

    final n = await _sync(api)
        .countGeoDataOnServer('p1', formDataFilters: {'AFD_NAME': 'E32'});

    expect(n, 7);
    expect(api.requested.single, contains('count_only=true'));
    expect(api.requested.single, contains('f=AFD_NAME:E32'));
  });

  test('countGeoDataOnServer encodes special chars in value', () async {
    final api = _FakeApi([_countPage(3)]);
    await _sync(api)
        .countGeoDataOnServer('p1', formDataFilters: {'AFD_NAME': 'E 3&2'});
    // form-encoding: spasi→'+', '&'→'%26'; separator ':' tetap literal.
    // Backend (Django QueryDict) mendekode '+'→spasi & '%26'→'&'.
    expect(api.requested.single, contains('f=AFD_NAME:E+3%262'));
  });
}
