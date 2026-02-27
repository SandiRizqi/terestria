import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Style configuration for a GeoJSON layer
class LayerStyle {
  final Color fillColor;
  final double fillOpacity;
  final Color strokeColor;
  final double strokeWidth;
  final double pointSize;

  const LayerStyle({
    required this.fillColor,
    required this.fillOpacity,
    required this.strokeColor,
    required this.strokeWidth,
    required this.pointSize,
  });

  LayerStyle copyWith({
    Color? fillColor,
    double? fillOpacity,
    Color? strokeColor,
    double? strokeWidth,
    double? pointSize,
  }) {
    return LayerStyle(
      fillColor: fillColor ?? this.fillColor,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      pointSize: pointSize ?? this.pointSize,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fillColor': fillColor.value,
      'fillOpacity': fillOpacity,
      'strokeColor': strokeColor.value,
      'strokeWidth': strokeWidth,
      'pointSize': pointSize,
    };
  }

  factory LayerStyle.fromJson(Map<String, dynamic> json) {
    return LayerStyle(
      fillColor: Color(json['fillColor'] as int),
      fillOpacity: (json['fillOpacity'] as num).toDouble(),
      strokeColor: Color(json['strokeColor'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      pointSize: (json['pointSize'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerStyle &&
          fillColor == other.fillColor &&
          fillOpacity == other.fillOpacity &&
          strokeColor == other.strokeColor &&
          strokeWidth == other.strokeWidth &&
          pointSize == other.pointSize;

  @override
  int get hashCode => Object.hash(
      fillColor, fillOpacity, strokeColor, strokeWidth, pointSize);
}

/// Model for a GeoJSON layer
class LayerModel {
  final String id;
  final String name;
  final String filePath;

  /// Canonical geometry type: 'Point', 'LineString', 'Polygon', 'Mixed'
  final String geometryType;

  final LayerStyle style;
  final bool isActive;
  final DateTime createdAt;

  /// Property key whose value is shown as label on the map
  final String? labelField;

  const LayerModel({
    required this.id,
    required this.name,
    required this.filePath,
    required this.geometryType,
    required this.style,
    required this.isActive,
    required this.createdAt,
    this.labelField,
  });

  // ──────────────────────────────────────────────────────
  // Computed helpers
  // ──────────────────────────────────────────────────────

  IconData get geometryIcon {
    switch (geometryType) {
      case 'Point':
      case 'MultiPoint':
        return Icons.place;
      case 'LineString':
      case 'MultiLineString':
        return Icons.timeline;
      case 'Polygon':
      case 'MultiPolygon':
        return Icons.crop_square;
      default:
        return Icons.layers;
    }
  }

  // ──────────────────────────────────────────────────────
  // CopyWith
  // ──────────────────────────────────────────────────────

  LayerModel copyWith({
    String? id,
    String? name,
    String? filePath,
    String? geometryType,
    LayerStyle? style,
    bool? isActive,
    DateTime? createdAt,
    String? labelField,
    bool clearLabelField = false,
  }) {
    return LayerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      geometryType: geometryType ?? this.geometryType,
      style: style ?? this.style,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      labelField: clearLabelField ? null : (labelField ?? this.labelField),
    );
  }

  // ──────────────────────────────────────────────────────
  // Serialization
  // ──────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'filePath': filePath,
      'geometryType': geometryType,
      'style': style.toJson(),
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'labelField': labelField,
    };
  }

  factory LayerModel.fromJson(Map<String, dynamic> json) {
    return LayerModel(
      id: json['id'] as String,
      name: json['name'] as String,
      filePath: json['filePath'] as String,
      geometryType: json['geometryType'] as String,
      style: LayerStyle.fromJson(json['style'] as Map<String, dynamic>),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      labelField: json['labelField'] as String?,
    );
  }
}
