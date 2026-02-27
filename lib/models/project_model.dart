import 'package:intl/intl.dart';

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
  final bool isSynced;
  final int? geoDataCount;
  final DateTime? syncedAt;
  final String? createdBy; // username yang membuat project

  Project({
    required this.id,
    required this.name,
    required this.description,
    required this.geometryType,
    required this.formFields,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
    this.syncedAt,
    this.createdBy,
    this.geoDataCount,
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
      'isSynced': isSynced,
      'syncedAt': syncedAt?.toIso8601String(),
      'createdBy': createdBy,
      'geoDataCount': geoDataCount,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    // Support both camelCase and snake_case from server
    final geometryTypeStr = json['geometryType'] ?? json['geometry_type'];
    final formFieldsData = json['formFields'] ?? json['form_fields'];
    final createdAtStr = json['createdAt'] ?? json['created_at'];
    final updatedAtStr = json['updatedAt'] ?? json['updated_at'];
    final isSyncedData = json['isSynced'] ?? json['is_synced'];
    final syncedAtStr = json['syncedAt'] ?? json['synced_at'];
    final createdByData = json['createdBy'] ?? json['created_by'];
    final geoDataCount = json['geoDataCount'] ?? json['geo_data_count'];
    
    return Project(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      geometryType: GeometryType.values.firstWhere(
        (e) => e.toString().split('.').last == geometryTypeStr,
      ),
      formFields: (formFieldsData as List)
          .map((f) => FormFieldModel.fromJson(f))
          .toList(),
      createdAt: DateTime.parse(createdAtStr),
      updatedAt: DateTime.parse(updatedAtStr),
      isSynced: isSyncedData ?? false,
      syncedAt: syncedAtStr != null ? DateTime.parse(syncedAtStr) : null,
      createdBy: createdByData,
      geoDataCount: geoDataCount,
    );
  }

  Project copyWith({
    String? name,
    String? description,
    GeometryType? geometryType,
    List<FormFieldModel>? formFields,
    DateTime? updatedAt,
    bool? isSynced,
    DateTime? syncedAt,
    String? createdBy,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      geometryType: geometryType ?? this.geometryType,
      formFields: formFields ?? this.formFields,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      syncedAt: syncedAt ?? this.syncedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
