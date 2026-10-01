import 'json_parse.dart';

/// Tipe field form. Nilai tersimpan per tipe: SPEC §3.1. Urutan tampil di
/// pembuat form diatur `field_type_info.dart`, bukan urutan enum ini.
enum FieldType {
  text,
  number,
  decimal,
  date,
  dropdown,
  checkbox,
  photo,
  textarea,
  multiselect,
  time,
  datetime,
  rating,
}

class FormFieldModel {
  final String id;
  final String label;
  final FieldType type;
  final bool required;
  final List<String>? options; // untuk dropdown & pilihan ganda
  final String? defaultValue;
  final int? maxPhotos; // untuk photo field
  final int? minPhotos; // untuk photo field - minimal jumlah foto

  /// Batas inklusif & satuan tampilan untuk angka/desimal (opsional).
  final double? min;
  final double? max;
  final String? unit;

  /// Nama tipe dari server yang tidak dikenal versi app ini (mis. tipe yang
  /// ditambahkan belakangan). Field-nya diperlakukan seperti [FieldType.text],
  /// tetapi nama ini yang dikirim balik — supaya menyimpan ulang form dari
  /// app ini tidak menurunkan tipenya.
  final String? unknownTypeName;

  FormFieldModel({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.options,
    this.defaultValue,
    this.maxPhotos,
    this.minPhotos,
    this.min,
    this.max,
    this.unit,
    this.unknownTypeName,
  });

  /// Nama tipe yang disimpan/dikirim: nama asli bila tipe tak dikenal.
  String get typeName => unknownTypeName ?? type.name;

  bool get isUnknownType => unknownTypeName != null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'type': typeName,
      'required': required,
      'options': options,
      'defaultValue': defaultValue,
      'maxPhotos': maxPhotos,
      'minPhotos': minPhotos,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (unit != null) 'unit': unit,
    };
  }

  /// Bentuk field di payload sync project (server). Key opsional hanya
  /// dikirim bila diisi.
  Map<String, dynamic> toSyncJson() {
    return {
      'id': id,
      'label': label,
      'type': typeName,
      'required': required,
      'options': options,
      if (defaultValue != null) 'defaultValue': defaultValue,
      if (minPhotos != null) 'minPhotos': minPhotos,
      if (maxPhotos != null) 'maxPhotos': maxPhotos,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (unit != null) 'unit': unit,
    };
  }

  /// Toleran: tipe tak dikenal → [FieldType.text] (nama aslinya disimpan di
  /// [unknownTypeName]), angka boleh int/string, key boleh camelCase atau
  /// snake_case.
  factory FormFieldModel.fromJson(Map<String, dynamic> json) {
    final label = parseString(json['label']) ?? '';
    final rawOptions = json['options'];
    final rawType = parseString(json['type']);
    final known = tryFieldTypeFromName(rawType);
    return FormFieldModel(
      id: parseString(json['id']) ?? label,
      label: label,
      type: known ?? FieldType.text,
      required: parseBool(json['required']),
      options: rawOptions is List
          ? rawOptions.map((e) => e.toString()).toList()
          : null,
      defaultValue: parseString(json['defaultValue'] ?? json['default_value']),
      maxPhotos: parseInt(json['maxPhotos'] ?? json['max_photos']),
      minPhotos: parseInt(json['minPhotos'] ?? json['min_photos']),
      min: parseDouble(json['min']),
      max: parseDouble(json['max']),
      unit: parseString(json['unit']),
      unknownTypeName: known == null ? rawType : null,
    );
  }
}

/// Nama tipe field (server/lokal, tak peka huruf besar) → [FieldType], atau
/// null bila tidak dikenal.
FieldType? tryFieldTypeFromName(Object? name) {
  final n = name?.toString().trim().toLowerCase();
  for (final t in FieldType.values) {
    if (t.name == n) return t;
  }
  return null;
}

/// Nama tipe field → [FieldType]. Tipe tak dikenal (mis. tipe baru dari
/// server) → [FieldType.text].
FieldType fieldTypeFromName(Object? name) =>
    tryFieldTypeFromName(name) ?? FieldType.text;
