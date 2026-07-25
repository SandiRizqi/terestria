import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/migration_service.dart';
import 'package:geoform_app/services/storage_service.dart';

class _FakeStorage implements StorageService {
  final List<GeoData> synced;
  final Map<String, Project> projects;
  final List<String> resetIds = [];

  _FakeStorage(this.synced, this.projects);

  @override
  Future<List<GeoData>> getSyncedGeoData({String? projectId}) async => synced;

  @override
  Future<Project?> getProjectById(String projectId) async => projects[projectId];

  @override
  Future<void> updateGeoDataSyncStatus(String geoDataId, bool isSynced,
      {DateTime? syncedAt}) async {
    if (!isSynced) resetIds.add(geoDataId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _ThrowingStorage implements StorageService {
  @override
  Future<List<GeoData>> getSyncedGeoData({String? projectId}) async =>
      throw Exception('db down');

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

GeoData _geo(String id, List<Map<String, dynamic>> photos) => GeoData(
      id: id,
      projectId: 'p1',
      formData: {'Photo': photos},
      points: [GeoPoint(latitude: 1, longitude: 2, timestamp: DateTime(2026, 1, 1))],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      isSynced: true,
    );

Map<String, dynamic> _photo({String? serverKey, required String localPath}) => {
      'name': localPath.split('/').last,
      'localPath': localPath,
      'serverKey': serverKey,
      'serverUrl': serverKey == null ? null : 'https://oss/$serverKey',
      'created': DateTime(2026, 1, 1).toIso8601String(),
      'updated': DateTime(2026, 1, 1).toIso8601String(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File existingPhoto;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('recovery');
    existingPhoto = File('${dir.path}/present.jpg')..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() {
    final parent = existingPhoto.parent;
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  test('resets synced records whose photos are incomplete', () async {
    final storage = _FakeStorage(
      [
        // recoverable: 1 missing serverKey but file still exists
        _geo('rec1', [
          _photo(serverKey: null, localPath: existingPhoto.path),
          _photo(serverKey: 'Production/ok.jpg', localPath: existingPhoto.path),
        ]),
        // clean: both uploaded → must be left synced
        _geo('rec2', [
          _photo(serverKey: 'Production/a.jpg', localPath: existingPhoto.path),
          _photo(serverKey: 'Production/b.jpg', localPath: existingPhoto.path),
        ]),
        // unrecoverable: missing serverKey and file is gone
        _geo('rec3', [
          _photo(serverKey: null, localPath: '/does/not/exist/gone.jpg'),
        ]),
      ],
      {'p1': _project()},
    );

    final result = await MigrationService()
        .recoverIncompletePhotoSyncs(storage: storage);

    expect(result.alreadyRun, isFalse);
    expect(result.scanned, 3);
    expect(result.resetForRetry, 1);
    expect(result.unrecoverable, 1);
    expect(storage.resetIds, containsAll(['rec1', 'rec3']));
    expect(storage.resetIds, isNot(contains('rec2')));
  });

  test('is idempotent: second run is a no-op guarded by the flag', () async {
    final storage = _FakeStorage(
      [
        _geo('rec1', [_photo(serverKey: null, localPath: existingPhoto.path)]),
      ],
      {'p1': _project()},
    );

    final first =
        await MigrationService().recoverIncompletePhotoSyncs(storage: storage);
    expect(first.alreadyRun, isFalse);
    expect(storage.resetIds, hasLength(1));

    final second =
        await MigrationService().recoverIncompletePhotoSyncs(storage: storage);
    expect(second.alreadyRun, isTrue);
    expect(storage.resetIds, hasLength(1), reason: 'no additional resets');
  });

  test('does not set the completion flag when the scan fails, so it retries',
      () async {
    final first = await MigrationService()
        .recoverIncompletePhotoSyncs(storage: _ThrowingStorage());
    expect(first.alreadyRun, isFalse);
    expect(first.scanned, 0);

    // A later run with a working storage must still perform recovery,
    // proving the failed run did not mark recovery as done.
    final good = _FakeStorage(
      [_geo('rec1', [_photo(serverKey: null, localPath: existingPhoto.path)])],
      {'p1': _project()},
    );
    final second =
        await MigrationService().recoverIncompletePhotoSyncs(storage: good);
    expect(second.alreadyRun, isFalse,
        reason: 'flag must not be set after a failed scan');
    expect(good.resetIds, contains('rec1'));
  });
}
