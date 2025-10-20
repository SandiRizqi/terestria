import 'form_field_model.dart';

enum GeometryType { point, line, polygon }

class Project {
  final String id;
  final String name;
  final String description;
  final GeometryType geometryType;
  final List<FormFieldModel> formFields;
  final DateTime createdAt;
  final DateTime updatedAt;

  Project({
    required this.id,
    required this.name,
    required this.description,
    required this.geometryType,
    required this.formFields,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'geometryType': geometryType.toString().split('.').last,
      'formFields': formFields.map((f) => f.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      geometryType: GeometryType.values.firstWhere(
        (e) => e.toString().split('.').last == json['geometryType'],
      ),
      formFields: (json['formFields'] as List)
          .map((f) => FormFieldModel.fromJson(f))
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  Project copyWith({
    String? name,
    String? description,
    GeometryType? geometryType,
    List<FormFieldModel>? formFields,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      geometryType: geometryType ?? this.geometryType,
      formFields: formFields ?? this.formFields,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
