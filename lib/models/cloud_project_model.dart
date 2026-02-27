/// Model untuk project dari cloud/server
class CloudProject {
  final String id;
  final String name;
  final String description;
  final String geometryType; // 'point', 'line', 'polygon'
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int dataCount; // Jumlah collected data
  final List<FormFieldData> formFields;

  CloudProject({
    required this.id,
    required this.name,
    required this.description,
    required this.geometryType,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.dataCount = 0,
    required this.formFields,
  });

  factory CloudProject.fromJson(Map<String, dynamic> json) {
    return CloudProject(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      geometryType: json['geometry_type'] as String,
      createdBy: json['created_by'] as String? ?? 'Unknown',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      dataCount: json['data_count'] as int? ?? 0,
      formFields: (json['form_fields'] as List<dynamic>?)
              ?.map((field) => FormFieldData.fromJson(field as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class FormFieldData {
  final String label;
  final String type;
  final bool required;
  final List<String>? options;
  final int? minPhotos;
  final int? maxPhotos;

  FormFieldData({
    required this.label,
    required this.type,
    required this.required,
    this.options,
    this.minPhotos,
    this.maxPhotos,
  });

  factory FormFieldData.fromJson(Map<String, dynamic> json) {
    return FormFieldData(
      label: json['label'] as String,
      type: json['type'] as String,
      required: json['required'] as bool? ?? false,
      options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      minPhotos: json['min_photos'] as int? ?? json['minPhotos'] as int?,
      maxPhotos: json['max_photos'] as int? ?? json['maxPhotos'] as int?,
    );
  }
}

/// Response wrapper untuk API
class CloudProjectResponse {
  final bool success;
  final String? message;
  final List<CloudProject> data;

  CloudProjectResponse({
    required this.success,
    this.message,
    required this.data,
  });

  factory CloudProjectResponse.fromJson(Map<String, dynamic> json) {
    return CloudProjectResponse(
      success: json['success'] as bool? ?? true,
      message: json['message'] as String?,
      data: (json['data'] as List<dynamic>?)
              ?.map((item) => CloudProject.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  factory CloudProjectResponse.error(String message) {
    return CloudProjectResponse(
      success: false,
      message: message,
      data: [],
    );
  }
}
