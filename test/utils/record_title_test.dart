import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/utils/record_title.dart';

/// Judul record bersama (daftar data & daftar pilihan feature di peta) —
/// diekstrak dari GeoDataListItem tanpa perubahan perilaku.

const _id = 'abcdef12-3456-7890-abcd-ef1234567890';

final _project = Project(
  id: 'p',
  name: 'Blok A',
  description: '',
  geometryType: GeometryType.point,
  formFields: [
    FormFieldModel(id: 'f', label: 'Dokumentasi', type: FieldType.photo),
    FormFieldModel(id: 'n', label: 'Nama', type: FieldType.text),
  ],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

GeoData _geo(Map<String, dynamic> form) => GeoData(
      id: _id,
      projectId: 'p',
      formData: form,
      points: const [],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  test('nilai field non-foto pertama; field foto dilewati (tipe project)', () {
    expect(
        recordTitle(_geo({'Dokumentasi': ['/a.jpg'], 'Nama': 'Pohon 7'}), _project),
        'Pohon 7');
  });

  test('tanpa project: field foto dikenali dari namanya', () {
    expect(recordTitle(_geo({'Foto Pohon': ['/a.jpg'], 'Blok': 'E32'}), null),
        'E32');
    expect(isPhotoFieldName('Gambar Lokasi', null), isTrue);
    expect(isPhotoFieldName('Nama', _project), isFalse);
    expect(isPhotoFieldName('Dokumentasi', _project), isTrue);
  });

  test('nilai panjang dipotong 40 karakter + "..."', () {
    final title = recordTitle(_geo({'Nama': 'x' * 60}), _project);
    expect(title, '${'x' * 40}...');
  });

  test('kosong / path file → "Survey Data #<8 karakter id>"', () {
    expect(recordTitle(_geo({}), _project), 'Survey Data #abcdef12');
    expect(recordTitle(_geo({'Nama': ''}), _project), 'Survey Data #abcdef12');
    expect(recordTitle(_geo({'Nama': '/storage/a.jpg'}), _project),
        'Survey Data #abcdef12');
  });
}
