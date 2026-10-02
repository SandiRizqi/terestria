import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/database_service.dart';

/// DB v8: kolom aturan project `projects.minAccuracy` (REAL, null = tanpa
/// aturan) dan `projects.uniqueFields` (JSON, '[]' = tanpa aturan).

Project _project({double? minAccuracy, List<String> uniqueFields = const []}) => Project(
      id: 'p1',
      name: 'Sensus TPH',
      description: 'Blok A',
      geometryType: GeometryType.polygon,
      formFields: [
        FormFieldModel(id: 'f1', label: 'WERKS', type: FieldType.text, required: true),
      ],
      createdAt: DateTime.utc(2026, 9, 30),
      updatedAt: DateTime.utc(2026, 10, 1),
      isSynced: true,
      syncedAt: DateTime.utc(2026, 10, 1, 1),
      createdBy: 'owner',
      collectors: const ['owner', 'budi'],
      minAccuracy: minAccuracy,
      uniqueFields: uniqueFields,
    );

void main() {
  test('versi DB naik ke 8', () {
    expect(DatabaseService.schemaVersion, 8);
  });

  test('migrasi v8 idempoten: kolom aturan hanya ditambah bila belum ada', () {
    final v7 = [
      {'cid': 0, 'name': 'id'},
      {'cid': 1, 'name': 'collectors'},
    ];
    expect(DatabaseService.missingColumns(v7, const ['minAccuracy', 'uniqueFields']),
        ['minAccuracy', 'uniqueFields']);
    expect(
        DatabaseService.missingColumns(
            [...v7, {'cid': 2, 'name': 'MINACCURACY'}, {'cid': 3, 'name': 'uniqueFields'}],
            const ['minAccuracy', 'uniqueFields']),
        isEmpty);
  });

  group('baris DB projects', () {
    test('aturan tersimpan dan terbaca kembali; isi lain utuh', () {
      final row = DatabaseService.projectToRow(
          _project(minAccuracy: 5, uniqueFields: ['WERKS', 'NO_TPH']));
      expect(row['minAccuracy'], 5.0);
      expect(jsonDecode(row['uniqueFields'] as String), ['WERKS', 'NO_TPH']);
      final back = DatabaseService.projectFromRow({...row});
      expect(back.minAccuracy, 5.0);
      expect(back.uniqueFields, ['WERKS', 'NO_TPH']);
      expect(back.name, 'Sensus TPH');
      expect(back.geometryType, GeometryType.polygon);
      expect(back.formFields.single.label, 'WERKS');
      expect(back.collectors, ['owner', 'budi']);
      expect(back.createdBy, 'owner');
      expect(back.isSynced, isTrue);
    });

    test('baris v7 (tanpa kolom aturan) terbaca tanpa aturan', () {
      final row = DatabaseService.projectToRow(_project(minAccuracy: 5, uniqueFields: ['WERKS']))
        ..remove('minAccuracy')
        ..remove('uniqueFields');
      final back = DatabaseService.projectFromRow(row);
      expect(back.minAccuracy, isNull);
      expect(back.uniqueFields, isEmpty);
    });

    test('isi kolom rusak tidak membuat project gagal dibaca', () {
      final row = {
        ...DatabaseService.projectToRow(_project()),
        'uniqueFields': '{rusak',
        'minAccuracy': 'x',
      };
      final back = DatabaseService.projectFromRow(row);
      expect(back.id, 'p1');
      expect(back.uniqueFields, isEmpty);
      expect(back.minAccuracy, isNull);
    });
  });
}
