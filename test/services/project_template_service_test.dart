import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/cloud_project_model.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/project_template_service.dart';

/// Template project dan project dari cloud dulu mengubah field `decimal` (dan
/// tipe lain yang tak ada di switch-nya) menjadi `text`, serta membuang
/// default/pengaturan field. Kini keduanya memakai JSON model yang sama.

Project _project() => Project(
      id: 'P1',
      name: 'Blok A',
      description: 'Sensus',
      geometryType: GeometryType.point,
      formFields: [
        FormFieldModel(
            id: 'f1',
            label: 'Diameter',
            type: FieldType.decimal,
            required: true,
            min: 0,
            max: 200,
            unit: 'cm',
            defaultValue: '10'),
        FormFieldModel.fromJson(
            {'id': 'f2', 'label': 'TTD', 'type': 'signature'}),
      ],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  test('template: ekspor lalu impor mempertahankan tipe dan pengaturan field',
      () {
    final service = ProjectTemplateService();
    final imported =
        service.importFromTemplate(service.exportAsTemplate(_project()), 'budi');
    final dia = imported.formFields.first;
    expect(dia.type, FieldType.decimal);
    expect((dia.min, dia.max, dia.unit, dia.defaultValue), (0.0, 200.0, 'cm', '10'));
    expect(dia.required, isTrue);
    expect(dia.id, isNot('f1')); // id field baru untuk project baru
    expect(imported.formFields.last.typeName, 'signature');
  });

  test('project dari cloud: field memakai model aslinya (decimal tetap decimal)',
      () {
    final original = _project().formFields.first;
    final data = FormFieldData(
      label: original.label,
      type: original.typeName,
      required: original.required,
      model: original,
    );
    expect(identical(data.toFormFieldModel(), original), isTrue);

    // Tanpa model (data lama): dibangun lewat fromJson — decimal tidak hilang.
    final legacy = FormFieldData(label: 'Luas', type: 'decimal', required: false);
    expect(legacy.toFormFieldModel().type, FieldType.decimal);
  });
}
