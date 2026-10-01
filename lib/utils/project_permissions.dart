import '../models/project_model.dart';

/// Apakah [username] pembuat [project]? Hanya pembuat yang boleh mengedit
/// project dan mengelola collector — sama dengan aturan server (gis-backend
/// `_can_edit_project`). Project lama tanpa pembuat hanya bisa diubah admin di
/// server, jadi di app tidak bisa diedit siapa pun.
bool isProjectCreator(Project project, String? username) {
  final creator = project.createdBy;
  if (username == null || creator == null) return false;
  return creator.trim().toLowerCase() == username.trim().toLowerCase();
}
