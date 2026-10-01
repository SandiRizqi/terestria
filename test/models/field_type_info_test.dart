import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/field_type_info.dart';
import 'package:geoform_app/models/form_field_model.dart';

/// Satu daftar nama, ikon, dan deskripsi tipe field — dipakai pembuat form,
/// layar pembuat project, dan detail project (dulu tiga peta terpisah yang
/// tidak mengenal `decimal`).

void main() {
  test('setiap tipe punya info: nama unik, ikon, deskripsi', () {
    final labels = <String>{};
    for (final type in FieldType.values) {
      final info = fieldTypeInfo(type);
      expect(info.type, type);
      expect(info.label, isNotEmpty);
      expect(info.description, isNotEmpty);
      expect(labels.add(info.label), isTrue, reason: 'label ganda: ${info.label}');
    }
  });

  test('tipe yang bisa dipilih di pembuat form: tipe yang inputnya sudah ada',
      () {
    expect(pickableFieldTypes.toSet(), {
      FieldType.text,
      FieldType.textarea,
      FieldType.number,
      FieldType.decimal,
      FieldType.date,
      FieldType.dropdown,
      FieldType.multiselect,
      FieldType.checkbox,
      FieldType.rating,
      FieldType.photo,
    });
  });

  test('nama tampilan field bertipe tak dikenal menyebut nama aslinya', () {
    final known = FormFieldModel(id: 'a', label: 'A', type: FieldType.decimal);
    final unknown = FormFieldModel.fromJson(
        {'id': 'b', 'label': 'B', 'type': 'signature'});
    expect(fieldTypeDisplayName(known), 'Decimal');
    expect(fieldTypeDisplayName(unknown), contains('signature'));
  });
}
