enum FieldType { text, number, date, dropdown, checkbox, photo }

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

  factory FormFieldModel.fromJson(Map<String, dynamic> json) {
    return FormFieldModel(
      id: json['id'],
      label: json['label'],
      type: FieldType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
      ),
      required: json['required'] ?? false,
      options: json['options'] != null ? List<String>.from(json['options']) : null,
      defaultValue: json['defaultValue'],
      maxPhotos: json['maxPhotos'],
      minPhotos: json['minPhotos'],
    );
  }
}
