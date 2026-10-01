import 'package:flutter/material.dart';

import 'layer_model.dart';
import 'project_model.dart';
import 'settings/app_settings.dart';

/// Style per feature (tampilan satu point/line/polygon record) — memakai ulang
/// [LayerStyle] karena propertinya sama dengan editor Layers. `null` = ikut
/// style default dari Settings (lihat [defaultFeatureStyle]).
///
/// Format JSON (DB lokal, payload sync, backend `validation.clean_style`):
/// warna `#RRGGBB` (tanpa alpha — opacity terpisah) + angka dalam rentang di
/// bawah. Key lain diabaikan saat dibaca (backend juga mengabaikannya):
///   {"fillColor": "#FF9800", "fillOpacity": 0.3, "strokeColor": "#E65100",
///    "strokeWidth": 2.0, "pointSize": 12.0}

const double featureMinOpacity = 0.05;
const double featureMaxOpacity = 1.0;
const double featureMinStrokeWidth = 0.5;
const double featureMaxStrokeWidth = 10.0;

/// Ukuran point 10–24 = diameter marker 20–48 dp di peta (lihat
/// `featurePointDiameter`), jadi setiap nilai terlihat bedanya dan semua nilai
/// Settings (8–24) muat.
const double featureMinPointSize = 10.0;
const double featureMaxPointSize = 24.0;

final _hexColor = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// Nilai-nilai style dijepit ke rentang kontrak (dipakai editor & sebelum
/// dikirim ke server, yang menolak nilai di luar rentang).
LayerStyle clampFeatureStyle(LayerStyle style) => LayerStyle(
      fillColor: style.fillColor,
      fillOpacity: style.fillOpacity
          .clamp(featureMinOpacity, featureMaxOpacity)
          .toDouble(),
      strokeColor: style.strokeColor,
      strokeWidth: style.strokeWidth
          .clamp(featureMinStrokeWidth, featureMaxStrokeWidth)
          .toDouble(),
      pointSize: style.pointSize
          .clamp(featureMinPointSize, featureMaxPointSize)
          .toDouble(),
    );

/// Style → JSON kontrak; `null` bila [style] null (ikut default).
Map<String, dynamic>? featureStyleToJson(LayerStyle? style) {
  if (style == null) return null;
  final s = clampFeatureStyle(style);
  return {
    'fillColor': _toHex(s.fillColor),
    'fillOpacity': s.fillOpacity,
    'strokeColor': _toHex(s.strokeColor),
    'strokeWidth': s.strokeWidth,
    'pointSize': s.pointSize,
  };
}

/// JSON kontrak → style. `null` bila null atau rusak (bukan map, warna bukan
/// `#RRGGBB`, angka hilang/tak valid); key asing diabaikan; angka di-clamp.
LayerStyle? featureStyleFromJson(Object? json) {
  if (json is! Map) return null;
  final fill = _fromHex(json['fillColor']);
  final stroke = _fromHex(json['strokeColor']);
  final opacity = _finite(json['fillOpacity']);
  final width = _finite(json['strokeWidth']);
  final size = _finite(json['pointSize']);
  if (fill == null ||
      stroke == null ||
      opacity == null ||
      width == null ||
      size == null) {
    return null;
  }
  return clampFeatureStyle(LayerStyle(
    fillColor: fill,
    fillOpacity: opacity,
    strokeColor: stroke,
    strokeWidth: width,
    pointSize: size,
  ));
}

/// Style yang dipakai untuk feature tanpa style sendiri — sama persis dengan
/// render default peta project sebelum fitur ini (warna & ukuran dari
/// Settings; line ber-opacity 0.8, point penuh).
LayerStyle defaultFeatureStyle(GeometryType type, AppSettings settings) {
  switch (type) {
    case GeometryType.point:
      return LayerStyle(
        fillColor: settings.pointColor,
        fillOpacity: 1.0,
        strokeColor: settings.pointColor,
        strokeWidth: settings.lineWidth,
        pointSize: settings.pointSize,
      );
    case GeometryType.line:
      return LayerStyle(
        fillColor: settings.lineColor,
        fillOpacity: 0.8,
        strokeColor: settings.lineColor,
        strokeWidth: settings.lineWidth,
        pointSize: settings.pointSize,
      );
    case GeometryType.polygon:
      return LayerStyle(
        fillColor: settings.polygonColor,
        fillOpacity: settings.polygonOpacity,
        strokeColor: settings.polygonColor,
        strokeWidth: settings.lineWidth,
        pointSize: settings.pointSize,
      );
  }
}

String _toHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color? _fromHex(Object? value) {
  if (value is! String || !_hexColor.hasMatch(value)) return null;
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}

double? _finite(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toDouble();
}
