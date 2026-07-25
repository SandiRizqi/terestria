import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/api_service.dart';
import 'package:geoform_app/services/photo_sync_service.dart';
import 'package:geoform_app/services/storage_service.dart';
import 'package:geoform_app/services/sync_service.dart';

/// Stub processFormDataForPush to return a fixed result (no network), while
/// delegating pendingPhotoUploads to the real implementation so the guard is
/// tested against genuine detection logic.
class _FakePhotoSyncService implements PhotoSyncService {
  final Map<String, dynamic> pushResult;
  final PhotoSyncService _real = PhotoSyncService();

  _FakePhotoSyncService(this.pushResult);

  @override
  Future<Map<String, dynamic>> processFormDataForPush(
    Map<String, dynamic> formData,
    Project project,
  ) async =>
      pushResult;

  @override
  List<PendingPhoto> pendingPhotoUploads(
    Map<String, dynamic> formData,
    Project project,
  ) =>
      _real.pendingPhotoUploads(formData, project);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

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
  Future<void> saveGeoData(GeoData geoData) async {
    saved.add(geoData);
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

GeoData _geoData() => GeoData(
      id: 'g1',
      projectId: 'p1',
      formData: const {'Photo': []},
      points: [GeoPoint(latitude: 1, longitude: 2, timestamp: DateTime(2026, 1, 1))],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Map<String, dynamic> _photo({String? serverKey}) => {
      'name': 'x.jpg',
      'localPath': '/does/not/exist/x.jpg',
      'serverKey': serverKey,
      'serverUrl': serverKey == null ? null : 'https://oss/x.jpg',
      'created': DateTime(2026, 1, 1).toIso8601String(),
      'updated': DateTime(2026, 1, 1).toIso8601String(),
    };

void main() {
  group('syncGeoData photo guard', () {
    test('keeps record unsynced and does not POST when a photo has no serverKey',
        () async {
      final partial = {
        'Photo': [
          _photo(serverKey: null), // upload failed
          _photo(serverKey: 'Production/ok.jpg'), // uploaded
        ],
      };
      final api = _FakeApiService();
      final storage = _FakeStorageService();
      final sync = SyncService.forTest(
        apiService: api,
        storageService: storage,
        photoSyncService: _FakePhotoSyncService(partial),
      );

      final result = await sync.syncGeoData(_geoData(), _project());

      expect(result.success, isFalse);
      expect(api.postCount, 0, reason: 'must not upload incomplete data');
      expect(storage.saved, hasLength(1));
      expect(storage.saved.single.isSynced, isFalse);
      // Partial progress persisted: the successful photo keeps its serverKey.
      final photos = storage.saved.single.formData['Photo'] as List;
      expect(photos[1]['serverKey'], 'Production/ok.jpg');
    });

    test('marks record synced and POSTs when all photos have a serverKey',
        () async {
      final complete = {
        'Photo': [
          _photo(serverKey: 'Production/a.jpg'),
          _photo(serverKey: 'Production/b.jpg'),
        ],
      };
      final api = _FakeApiService();
      final storage = _FakeStorageService();
      final sync = SyncService.forTest(
        apiService: api,
        storageService: storage,
        photoSyncService: _FakePhotoSyncService(complete),
      );

      final result = await sync.syncGeoData(_geoData(), _project());

      expect(result.success, isTrue);
      expect(api.postCount, 1);
      expect(storage.saved, hasLength(1));
      expect(storage.saved.single.isSynced, isTrue);
    });
  });
}
