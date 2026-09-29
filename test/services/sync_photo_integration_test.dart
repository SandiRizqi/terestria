import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/api_service.dart';
import 'package:geoform_app/services/photo_sync_service.dart';
import 'package:geoform_app/services/storage_service.dart';
import 'package:geoform_app/services/sync_service.dart';

/// End-to-end guard test: uses the REAL PhotoSyncService.processFormDataForPush
/// so the actual photo-processing path is exercised together with the sync
/// guard. Only the network POST and local storage are faked.
class _FakeApiService implements ApiService {
  int postCount = 0;

  @override
  Future<http.Response> post(String endpoint,
      {Map<String, String>? headers, dynamic body}) async {
    postCount++;
    return http.Response('{"message":"ok"}', 200);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeStorageService implements StorageService {
  final List<GeoData> saved = [];

  @override
  Future<void> saveGeoData(GeoData geoData) async => saved.add(geoData);

  @override
  Future<bool> saveGeoDataIfUnchanged(GeoData geoData,
      {required DateTime expectedUpdatedAt}) async {
    saved.add(geoData);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Project _project() => Project(
      id: 'p1',
      name: 'Test',
      description: '',
      geometryType: GeometryType.point,
      formFields: [
        FormFieldModel(id: 'f1', label: 'Photo', type: FieldType.photo),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

GeoData _geo(List<Map<String, dynamic>> photos) => GeoData(
      id: 'g1',
      projectId: 'p1',
      formData: {'Photo': photos},
      points: [GeoPoint(latitude: 1, longitude: 2, timestamp: DateTime(2026, 1, 1))],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Map<String, dynamic> _photo({
  required String localPath,
  String? serverKey,
  String? serverUrl,
}) =>
    {
      'name': localPath.split('/').last,
      'localPath': localPath,
      'serverKey': serverKey,
      'serverUrl': serverUrl,
      'created': DateTime(2026, 1, 1).toIso8601String(),
      'updated': DateTime(2026, 1, 1).toIso8601String(),
    };

void main() {
  SyncService buildSync(_FakeApiService api, _FakeStorageService storage) =>
      SyncService.forTest(
        apiService: api,
        storageService: storage,
        // Real service — exercises the actual upload/skip logic.
        photoSyncService: PhotoSyncService(),
      );

  test(
      'real photo processing: an un-uploadable photo (missing file) keeps the '
      'record unsynced and skips the server POST', () async {
    final api = _FakeApiService();
    final storage = _FakeStorageService();
    // serverUrl null + local file that does not exist → uploadSinglePhoto
    // returns null → serverKey stays null → guard must block sync.
    final geo = _geo([
      _photo(localPath: '/does/not/exist/missing.jpg'),
    ]);

    final result = await buildSync(api, storage).syncGeoData(geo, _project());

    expect(result.success, isFalse);
    expect(api.postCount, 0);
    expect(storage.saved.single.isSynced, isFalse);
  });

  test(
      'real photo processing: an already-uploaded photo (has serverKey) syncs '
      'and POSTs', () async {
    final api = _FakeApiService();
    final storage = _FakeStorageService();
    // serverUrl set → processFormDataForPush skips re-upload, keeps serverKey.
    final geo = _geo([
      _photo(
        localPath: '/does/not/exist/already.jpg',
        serverKey: 'Production/already.jpg',
        serverUrl: 'https://oss/already.jpg',
      ),
    ]);

    final result = await buildSync(api, storage).syncGeoData(geo, _project());

    expect(result.success, isTrue);
    expect(api.postCount, 1);
    expect(storage.saved.last.isSynced, isTrue);
  });
}
