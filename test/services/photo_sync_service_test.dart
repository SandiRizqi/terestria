import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/photo_sync_service.dart';

Project _projectWithPhotoField({String label = 'Photo'}) {
  return Project(
    id: 'p1',
    name: 'Test',
    description: '',
    geometryType: GeometryType.point,
    formFields: [
      FormFieldModel(id: 'f1', label: label, type: FieldType.photo),
      FormFieldModel(id: 'f2', label: 'NOTE', type: FieldType.text),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

Map<String, dynamic> _photoItem({
  required String name,
  required String localPath,
  String? serverKey,
  String? serverUrl,
}) {
  return {
    'name': name,
    'localPath': localPath,
    'serverKey': serverKey,
    'serverUrl': serverUrl,
    'created': DateTime(2026, 1, 1).toIso8601String(),
    'updated': DateTime(2026, 1, 1).toIso8601String(),
  };
}

void main() {
  final service = PhotoSyncService();

  group('pendingPhotoUploads', () {
    test('returns only photos without a serverKey', () {
      final formData = {
        'Photo': [
          _photoItem(name: 'a.jpg', localPath: '/tmp/a.jpg'), // pending
          _photoItem(
            name: 'b.jpg',
            localPath: '/tmp/b.jpg',
            serverKey: 'Production/b.jpg',
            serverUrl: 'https://oss/b.jpg',
          ), // uploaded
          _photoItem(
            name: 'c.jpg',
            localPath: '/tmp/c.jpg',
            serverKey: 'Production/c.jpg',
            serverUrl: 'https://oss/c.jpg',
          ), // uploaded
        ],
        'NOTE': 'Lengkap',
      };

      final pending = service.pendingPhotoUploads(formData, _projectWithPhotoField());

      expect(pending, hasLength(1));
      expect(pending.first.name, 'a.jpg');
      expect(pending.first.fieldLabel, 'Photo');
    });

    test('ignores photos whose localPath is already an http url', () {
      final formData = {
        'Photo': [
          _photoItem(name: 'remote.jpg', localPath: 'https://oss/remote.jpg'),
        ],
      };

      final pending = service.pendingPhotoUploads(formData, _projectWithPhotoField());

      expect(pending, isEmpty);
    });

    test('flags fileExists=false when the local file is missing', () {
      final formData = {
        'Photo': [
          _photoItem(name: 'gone.jpg', localPath: '/does/not/exist/gone.jpg'),
        ],
      };

      final pending = service.pendingPhotoUploads(formData, _projectWithPhotoField());

      expect(pending, hasLength(1));
      expect(pending.first.fileExists, isFalse);
    });

    test('flags fileExists=true when the local file is present', () {
      final tmpDir = Directory.systemTemp.createTempSync('pss_test');
      final file = File('${tmpDir.path}/present.jpg')..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      final formData = {
        'Photo': [
          _photoItem(name: 'present.jpg', localPath: file.path),
        ],
      };

      final pending = service.pendingPhotoUploads(formData, _projectWithPhotoField());

      expect(pending, hasLength(1));
      expect(pending.first.fileExists, isTrue);
    });

    test('ignores non-photo fields entirely', () {
      final formData = {'NOTE': '/tmp/not-a-photo.jpg'};

      final pending = service.pendingPhotoUploads(formData, _projectWithPhotoField());

      expect(pending, isEmpty);
    });
  });

  group('needsUpload (keyed on serverKey)', () {
    PhotoMetadata meta({String? serverKey, String? serverUrl, String localPath = '/tmp/a.jpg'}) =>
        PhotoMetadata(
          name: 'a.jpg',
          localPath: localPath,
          serverKey: serverKey,
          serverUrl: serverUrl,
          created: DateTime(2026, 1, 1),
          updated: DateTime(2026, 1, 1),
        );

    test('true when serverKey is null and localPath is local', () {
      expect(service.needsUpload(meta(serverKey: null)), isTrue);
    });

    test('false when serverKey is set (even if serverUrl is null/stale)', () {
      // Regression: must NOT re-upload just because serverUrl is missing.
      expect(service.needsUpload(meta(serverKey: 'Production/a.jpg', serverUrl: null)), isFalse);
    });

    test('false when serverKey is set and serverUrl present', () {
      expect(
        service.needsUpload(meta(serverKey: 'Production/a.jpg', serverUrl: 'https://oss/a.jpg')),
        isFalse,
      );
    });

    test('false when localPath is an http url regardless of serverKey', () {
      expect(service.needsUpload(meta(serverKey: null, localPath: 'https://oss/a.jpg')), isFalse);
    });
  });
}
