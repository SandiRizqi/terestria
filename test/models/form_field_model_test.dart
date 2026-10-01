import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';

/// Definisi field form (SPEC §3.2): 5 tipe baru, `min`/`max`/`unit`, dan nama
/// tipe tak dikenal dipertahankan saat form disimpan ulang.

void main() {
  group('nama tipe', () {
    test('tipe baru dikenali (tak peka huruf besar/kecil)', () {
      expect(fieldTypeFromName('textarea'), FieldType.textarea);
      expect(fieldTypeFromName('MultiSelect'), FieldType.multiselect);
      expect(fieldTypeFromName('time'), FieldType.time);
      expect(fieldTypeFromName('datetime'), FieldType.datetime);
      expect(fieldTypeFromName('rating'), FieldType.rating);
      expect(fieldTypeFromName('decimal'), FieldType.decimal);
    });

    test('tipe tak dikenal: diperlakukan seperti teks, nama asli dipertahankan',
        () {
      final field = FormFieldModel.fromJson(
          {'id': 'f1', 'label': 'TTD', 'type': 'signature', 'required': true});
      expect(field.type, FieldType.text);
      expect(field.typeName, 'signature');
      expect(field.isUnknownType, isTrue);
      expect(field.toJson()['type'], 'signature');
      expect(field.toSyncJson()['type'], 'signature');
      expect(FormFieldModel.fromJson(field.toJson()).typeName, 'signature');
    });

    test('tipe dikenal: typeName = nama enum', () {
      final field = FormFieldModel(id: 'f', label: 'L', type: FieldType.rating);
      expect(field.typeName, 'rating');
      expect(field.isUnknownType, isFalse);
    });
  });

  group('min / max / unit', () {
    test('dibaca dari angka atau teks angka, lalu round-trip', () {
      final field = FormFieldModel.fromJson({
        'id': 'f1',
        'label': 'Diameter',
        'type': 'decimal',
        'min': 0,
        'max': '200',
        'unit': 'cm',
      });
      expect((field.min, field.max, field.unit), (0.0, 200.0, 'cm'));
      final again = FormFieldModel.fromJson(field.toJson());
      expect((again.min, again.max, again.unit), (0.0, 200.0, 'cm'));
    });

    test('tidak diisi → null dan tidak ikut payload sync', () {
      final json =
          FormFieldModel(id: 'f', label: 'L', type: FieldType.number).toSyncJson();
      expect(json.containsKey('min'), isFalse);
      expect(json.containsKey('max'), isFalse);
      expect(json.containsKey('unit'), isFalse);
    });
  });

  test('payload sync: key sama dengan payload lama + pengaturan baru', () {
    final json = FormFieldModel(
      id: 'f1',
      label: 'Diameter',
      type: FieldType.decimal,
      required: true,
      min: 0,
      max: 200,
      unit: 'cm',
      defaultValue: '10',
    ).toSyncJson();
    expect(json, {
      'id': 'f1',
      'label': 'Diameter',
      'type': 'decimal',
      'required': true,
      'options': null,
      'defaultValue': '10',
      'min': 0.0,
      'max': 200.0,
      'unit': 'cm',
    });
    final photo = FormFieldModel(
            id: 'p', label: 'Photo', type: FieldType.photo, minPhotos: 1, maxPhotos: 3)
        .toSyncJson();
    expect((photo['minPhotos'], photo['maxPhotos']), (1, 3));
    expect(photo.containsKey('defaultValue'), isFalse);
  });
}
