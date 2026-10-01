import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/utils/project_permissions.dart';

/// Hanya pembuat project yang boleh mengedit project / mengelola collector —
/// sama dengan aturan server (gis-backend `_can_edit_project`). Project lama
/// tanpa pembuat hanya bisa diubah admin di server, jadi di app pun tidak.

Project _project(String? createdBy) => Project(
      id: 'P1',
      name: 'Blok A',
      description: '',
      geometryType: GeometryType.point,
      formFields: const [],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      createdBy: createdBy,
    );

void main() {
  test('pembuat (abaikan huruf besar/kecil & spasi) → boleh', () {
    expect(isProjectCreator(_project('Budi'), ' budi '), isTrue);
  });

  test('user lain atau belum login → tidak boleh', () {
    expect(isProjectCreator(_project('budi'), 'sari'), isFalse);
    expect(isProjectCreator(_project('budi'), null), isFalse);
  });

  test('project tanpa pembuat → tidak boleh (server hanya mengizinkan admin)',
      () {
    expect(isProjectCreator(_project(null), 'budi'), isFalse);
  });
}
