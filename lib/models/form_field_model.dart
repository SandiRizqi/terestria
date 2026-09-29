import 'json_parse.dart';

enum FieldType { text, number, decimal, date, dropdown, checkbox, photo }

class FormFieldModel {
  final String id;
  final String label;
  final FieldType type;
  final bool required;
  final List<String>? options; // untuk dropdown
  final String? defaultValue;
  final int? maxPhotos; // untuk photo field
  final int? minPhotos; // untuk photo field - minimal jumlah foto

  FormFieldModel({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.options,
    this.defaultValue,
    this.maxPhotos,
    this.minPhotos,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'type': type.toString().split('.').last,
      'required': required,
      'options': options,
      'defaultValue': defaultValue,
      'maxPhotos': maxPhotos,
      'minPhotos': minPhotos,
    };
  }

  /// Toleran: tipe tak dikenal → [FieldType.text] (bukan melempar dan
  /// menggagalkan seluruh project), angka boleh int/string, key boleh
  /// camelCase atau snake_case.
  factory FormFieldModel.fromJson(Map<String, dynamic> json) {
    final label = parseString(json['label']) ?? '';
    final rawOptions = json['options'];
    return FormFieldModel(
      id: parseString(json['id']) ?? label,
      label: label,
      type: fieldTypeFromName(json['type']),
      required: parseBool(json['required']),
      options: rawOptions is List
          ? rawOptions.map((e) => e.toString()).toList()
          : null,
      defaultValue: parseString(json['defaultValue'] ?? json['default_value']),
      maxPhotos: parseInt(json['maxPhotos'] ?? json['max_photos']),
      minPhotos: parseInt(json['minPhotos'] ?? json['min_photos']),
    );
  }
}

/// Nama tipe field (server/lokal, tak peka huruf besar) → [FieldType].
/// Tipe tak dikenal (mis. tipe baru dari server) → [FieldType.text].
FieldType fieldTypeFromName(Object? name) {
  final n = name?.toString().trim().toLowerCase();
  for (final t in FieldType.values) {
    if (t.name == n) return t;
  }
  return FieldType.text;
}
