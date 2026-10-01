import '../models/form_field_model.dart';
import '../models/geo_data_model.dart';
import '../models/project_model.dart';
import 'field_values.dart';

/// Judul, deteksi field foto, dan teks tampilan isian record survei — dipakai
/// daftar data (GeoDataListItem), daftar pilihan feature di peta, dan dialog
/// detail record.

/// Field project dengan label [fieldName], atau null.
FormFieldModel? projectField(String fieldName, Project? project) =>
    project?.formFields.where((f) => f.label == fieldName).firstOrNull;

/// Field foto: menurut tipe field project bila field-nya dikenal, selain itu
/// dari namanya (photo/image/picture/foto/gambar).
bool isPhotoFieldName(String fieldName, Project? project) {
  final field = projectField(fieldName, project);
  if (field != null) return field.type == FieldType.photo;
  final lowerName = fieldName.toLowerCase();
  return lowerName.contains('photo') ||
      lowerName.contains('image') ||
      lowerName.contains('picture') ||
      lowerName.contains('foto') ||
      lowerName.contains('gambar');
}

/// Teks tampilan satu isian: terformat sesuai tipe field project
/// ([displayFieldValue]: `4 / 5`, `35.5 cm`, Yes/No, …); isian tanpa field di
/// project tampil apa adanya.
String recordValueText(String fieldName, Object? value, Project? project) {
  final field = projectField(fieldName, project);
  if (field != null) return displayFieldValue(field, value);
  return value?.toString() ?? '';
}

/// Nilai terformat field non-foto pertama (maks 40 karakter + "..."); tidak
/// ada, kosong, atau path file → "Survey Data #<8 karakter id>".
String recordTitle(GeoData data, Project? project) {
  final entry = data.formData.entries
      .where((e) => !isPhotoFieldName(e.key, project))
      .firstOrNull;
  if (entry != null) {
    final text = recordValueText(entry.key, entry.value, project);
    if (text.isNotEmpty && !text.startsWith('/')) {
      return text.length > 40 ? '${text.substring(0, 40)}...' : text;
    }
  }
  final id = data.id;
  return 'Survey Data #${id.length > 8 ? id.substring(0, 8) : id}';
}
