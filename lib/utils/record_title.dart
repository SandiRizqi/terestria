import '../models/form_field_model.dart';
import '../models/geo_data_model.dart';
import '../models/project_model.dart';

/// Judul & deteksi field foto untuk record survei — dipakai daftar data
/// (GeoDataListItem) dan daftar pilihan feature di peta.

/// Field foto: menurut tipe field project bila field-nya dikenal, selain itu
/// dari namanya (photo/image/picture/foto/gambar).
bool isPhotoFieldName(String fieldName, Project? project) {
  if (project != null) {
    final field =
        project.formFields.where((f) => f.label == fieldName).firstOrNull;
    if (field != null) return field.type == FieldType.photo;
  }
  final lowerName = fieldName.toLowerCase();
  return lowerName.contains('photo') ||
      lowerName.contains('image') ||
      lowerName.contains('picture') ||
      lowerName.contains('foto') ||
      lowerName.contains('gambar');
}

/// Nilai field non-foto pertama (maks 40 karakter + "..."); kosong atau path
/// file → "Survey Data #<8 karakter id>".
String recordTitle(GeoData data, Project? project) {
  if (data.formData.isNotEmpty) {
    final firstNonPhotoEntry = data.formData.entries.firstWhere(
      (entry) => !isPhotoFieldName(entry.key, project),
      orElse: () => data.formData.entries.first,
    );
    final firstValue = firstNonPhotoEntry.value.toString();
    if (firstValue.isNotEmpty && !firstValue.startsWith('/')) {
      return firstValue.length > 40
          ? '${firstValue.substring(0, 40)}...'
          : firstValue;
    }
  }
  final id = data.id;
  return 'Survey Data #${id.length > 8 ? id.substring(0, 8) : id}';
}
