import 'package:intl/intl.dart';

import 'form_field_model.dart';
import 'json_parse.dart';

enum GeometryType { point, line, polygon }

/// Nama geometri (server/lokal, tak peka huruf besar) → [GeometryType].
/// Nilai tak dikenal → [GeometryType.point] agar project tetap bisa dimuat.
GeometryType geometryTypeFromName(Object? name) {
  final n = name?.toString().trim().toLowerCase();
  switch (n) {
    case 'line':
    case 'linestring':
    case 'polyline':
      return GeometryType.line;
    case 'polygon':
      return GeometryType.polygon;
    default:
      return GeometryType.point;
  }
}

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
  final List<String> collectors; // daftar username collectors/collaborators

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
    this.collectors = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'geometryType': geometryType.toString().split('.').last,
      'formFields': formFields.map((f) => f.toJson()).toList(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'isSynced': isSynced,
      'syncedAt': syncedAt?.toUtc().toIso8601String(),
      'createdBy': createdBy,
      'geoDataCount': geoDataCount,
      'collectors': collectors,
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
    final collectorsData = json['collectors'];

    final id = parseString(json['id']);
    if (id == null) throw const FormatException('Project without "id"');
    return Project(
      id: id,
      name: parseString(json['name']) ?? 'Untitled project',
      description: json['description']?.toString() ?? '',
      geometryType: geometryTypeFromName(geometryTypeStr),
      formFields: formFieldsData is List
          ? formFieldsData
              .map((f) =>
                  FormFieldModel.fromJson(Map<String, dynamic>.from(f as Map)))
              .toList()
          : <FormFieldModel>[],
      createdAt: requireDateTime(createdAtStr, 'created_at'),
      updatedAt: requireDateTime(updatedAtStr, 'updated_at'),
      isSynced: parseBool(isSyncedData),
      syncedAt: parseDateTime(syncedAtStr),
      createdBy: parseString(createdByData),
      geoDataCount: parseInt(geoDataCount),
      collectors: collectorsData is List
          ? collectorsData.map((e) => e.toString()).toList()
          : const [],
    );
  }

  /// Project dari respons server: disimpan sebagai SUDAH sinkron. Server tidak
  /// mengirim `isSynced`, jadi dengan [Project.fromJson] saja setiap project
  /// hasil tarik dianggap belum sync dan di-push balik oleh semua HP —
  /// termasuk HP collector — dan bisa menimpa form yang lebih baru di server.
  factory Project.fromServerJson(Map<String, dynamic> json, {DateTime? now}) =>
      Project.fromJson({
        ...json,
        'isSynced': true,
        'syncedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      });

  Project copyWith({
    String? name,
    String? description,
    GeometryType? geometryType,
    List<FormFieldModel>? formFields,
    DateTime? updatedAt,
    bool? isSynced,
    DateTime? syncedAt,
    String? createdBy,
    List<String>? collectors,
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
      collectors: collectors ?? this.collectors,
    );
  }
}
