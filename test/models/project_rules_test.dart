import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/cloud_project_model.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/sync_service.dart';

/// Aturan project (SPEC §3.5): `minAccuracy` (meter, null = tanpa aturan)
/// dan `uniqueFields` (label field kombinasi unik, [] = tanpa aturan).

Map<String, dynamic> _json([Map<String, dynamic> extra = const {}]) => {
      'id': 'P1',
      'name': 'Sensus TPH',
      'description': '',
      'geometryType': 'point',
      'formFields': const [],
      'createdAt': '2026-10-01T00:00:00Z',
      'updatedAt': '2026-10-01T00:00:00Z',
      ...extra,
    };

void main() {
  test('dibaca dari respons server (camelCase) dan bentuk snake_case', () {
    final p = Project.fromJson(_json({'minAccuracy': 5, 'uniqueFields': ['WERKS', 'NO_TPH']}));
    expect(p.minAccuracy, 5.0);
    expect(p.uniqueFields, ['WERKS', 'NO_TPH']);
    final q = Project.fromJson(_json({'min_accuracy': '2.5', 'unique_fields': ['A']}));
    expect(q.minAccuracy, 2.5);
    expect(q.uniqueFields, ['A']);
  });

  test('tanpa key, nilai rusak, atau batas bukan positif → tanpa aturan', () {
    final p = Project.fromJson(_json());
    expect(p.minAccuracy, isNull);
    expect(p.uniqueFields, isEmpty);
    final q = Project.fromJson(_json({'minAccuracy': 'x', 'uniqueFields': 'WERKS'}));
    expect(q.minAccuracy, isNull);
    expect(q.uniqueFields, isEmpty);
    expect(Project.fromJson(_json({'minAccuracy': 0})).minAccuracy, isNull);
  });

  test('toJson → fromJson utuh', () {
    final p = Project.fromJson(_json({'minAccuracy': 3.5, 'uniqueFields': ['WERKS']}));
    final back = Project.fromJson(p.toJson());
    expect(back.minAccuracy, 3.5);
    expect(back.uniqueFields, ['WERKS']);
  });

  test('copyWith mengubah, mempertahankan, dan menghapus aturan', () {
    final p = Project.fromJson(_json({'minAccuracy': 5, 'uniqueFields': ['WERKS']}));
    expect(p.copyWith(name: 'x').minAccuracy, 5);
    expect(p.copyWith(name: 'x').uniqueFields, ['WERKS']);
    expect(p.copyWith(minAccuracy: 3).minAccuracy, 3);
    expect(p.copyWith(clearMinAccuracy: true).minAccuracy, isNull);
    expect(p.copyWith(uniqueFields: const []).uniqueFields, isEmpty);
  });

  group('project dari cloud (dialog "Add from cloud")', () {
    CloudProject cloud() => CloudProject(
          id: 'C1',
          name: 'Sensus TPH',
          description: 'Blok A',
          geometryType: 'polygon',
          createdBy: 'owner',
          createdAt: DateTime.utc(2026, 9, 30),
          updatedAt: DateTime.utc(2026, 10, 1),
          formFields: [
            FormFieldData(
                label: 'WERKS',
                type: 'text',
                required: true,
                model: FormFieldModel(
                    id: 'f1', label: 'WERKS', type: FieldType.text, required: true)),
          ],
          collectors: const ['owner', 'budi'],
          minAccuracy: 5,
          uniqueFields: const ['WERKS'],
        );

    test('membawa aturan, field, dan ditandai sudah sync', () {
      final now = DateTime.utc(2026, 10, 2);
      final p = cloud().toProject(now: now);
      expect(p.minAccuracy, 5);
      expect(p.uniqueFields, ['WERKS']);
      expect(p.geometryType, GeometryType.polygon);
      expect(p.formFields.single.id, 'f1');
      expect(p.collectors, ['owner', 'budi']);
      expect(p.isSynced, isTrue);
      expect(p.syncedAt, now);
    });

    test('CloudProject.fromJson membaca aturan', () {
      final c = CloudProject.fromJson({
        'id': 'C1',
        'name': 'Sensus TPH',
        'geometry_type': 'point',
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
        'min_accuracy': 2.5,
        'unique_fields': ['A', 'B'],
      });
      expect(c.minAccuracy, 2.5);
      expect(c.uniqueFields, ['A', 'B']);
    });
  });

  group('sync', () {
    test('payload push project memuat aturan (snake_case)', () {
      final p = Project.fromJson(_json({'minAccuracy': 5, 'uniqueFields': ['WERKS']}));
      final payload = SyncService.projectPayload(p);
      expect(payload['min_accuracy'], 5.0);
      expect(payload['unique_fields'], ['WERKS']);
      expect(payload['id'], 'P1');
      expect(payload['form_fields'], isEmpty);
    });

    test('payload project tanpa aturan mengirim null / []', () {
      final payload = SyncService.projectPayload(Project.fromJson(_json()));
      expect(payload.containsKey('min_accuracy'), isTrue);
      expect(payload['min_accuracy'], isNull);
      expect(payload['unique_fields'], isEmpty);
    });

    test('pull: parseProjectFromServer membaca aturan', () {
      final p = SyncService.parseProjectFromServer(
          _json({'minAccuracy': 7.5, 'uniqueFields': ['WERKS', 'BLOCK_NAME']}));
      expect(p.minAccuracy, 7.5);
      expect(p.uniqueFields, ['WERKS', 'BLOCK_NAME']);
    });
  });
}
