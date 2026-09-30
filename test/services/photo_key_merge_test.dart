import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/photo_sync_service.dart';

/// Layar edit menyimpan dari snapshot saat dibuka. Bila auto-sync mengunggah
/// foto selama user mengedit, `serverKey` hasil upload tak boleh hilang
/// (dulu hilang → foto diunggah ulang, duplikat di OSS).

final _project = Project(
  id: 'p1',
  name: 'Blocks',
  description: '',
  geometryType: GeometryType.point,
  formFields: [
    FormFieldModel(id: 'f1', label: 'Photo', type: FieldType.photo),
    FormFieldModel(id: 'f2', label: 'Note', type: FieldType.text),
  ],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Map<String, dynamic> _photo(String name, {String? key, String? url}) => {
      'name': name,
      'localPath': '/photos/$name',
      'serverKey': key,
      'serverUrl': url,
    };

void main() {
  test('serverKey/serverUrl hasil upload disalin dari versi DB terbaru', () {
    final edited = {
      'Photo': [_photo('a.jpg'), _photo('b.jpg')],
      'Note': 'edited',
    };
    final latest = {
      'Photo': [_photo('a.jpg', key: 'k/a.jpg', url: 'https://oss/a.jpg'),
                _photo('b.jpg')],
      'Note': 'old',
    };

    final merged =
        PhotoSyncService.mergeUploadedPhotoKeys(edited, latest, _project);

    final photos = (merged['Photo'] as List).cast<Map>();
    expect(photos[0]['serverKey'], 'k/a.jpg');
    expect(photos[0]['serverUrl'], 'https://oss/a.jpg');
    expect(photos[1]['serverKey'], isNull);
    expect(merged['Note'], 'edited', reason: "the user's edit wins");
    // Input tak diubah.
    expect((edited['Photo'] as List).first['serverKey'], isNull);
  });

  test('foto yang dihapus user tetap terhapus; key yang sudah ada tak ditimpa',
      () {
    final edited = {
      'Photo': [_photo('b.jpg', key: 'k/b-new.jpg')],
    };
    final latest = {
      'Photo': [
        _photo('a.jpg', key: 'k/a.jpg'),
        _photo('b.jpg', key: 'k/b-old.jpg'),
      ],
    };

    final merged =
        PhotoSyncService.mergeUploadedPhotoKeys(edited, latest, _project);

    final photos = (merged['Photo'] as List).cast<Map>();
    expect(photos.map((p) => p['name']), ['b.jpg']);
    expect(photos.single['serverKey'], 'k/b-new.jpg');
  });

  test('nilai foto bukan daftar (format lama) dibiarkan apa adanya', () {
    final merged = PhotoSyncService.mergeUploadedPhotoKeys(
        {'Photo': '/photos/a.jpg'},
        {'Photo': [_photo('a.jpg', key: 'k/a.jpg')]},
        _project);
    expect(merged['Photo'], '/photos/a.jpg');
  });
}
