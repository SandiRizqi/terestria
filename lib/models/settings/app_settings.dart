import 'package:flutter/material.dart';

/// Unit untuk pengukuran luas
enum AreaUnit {
  squareMeters('Square Meters', 'm²', 1.0),
  hectares('Hectares', 'ha', 10000.0),
  squareKilometers('Square Kilometers', 'km²', 1000000.0),
  acres('Acres', 'ac', 4046.86);

  final String name;
  final String symbol;
  final double toSquareMeters; // conversion factor

  const AreaUnit(this.name, this.symbol, this.toSquareMeters);

  double convert(double valueInSquareMeters) {
    return valueInSquareMeters / toSquareMeters;
  }

  double toM2(double value) {
    return value * toSquareMeters;
  }
}

/// Unit untuk pengukuran panjang/jarak
enum LengthUnit {
  meters('Meters', 'm', 1.0),
  kilometers('Kilometers', 'km', 1000.0),
  feet('Feet', 'ft', 0.3048),
  miles('Miles', 'mi', 1609.34);

  final String name;
  final String symbol;
  final double toMeters; // conversion factor

  const LengthUnit(this.name, this.symbol, this.toMeters);

  double convert(double valueInMeters) {
    return valueInMeters / toMeters;
  }

  double toM(double value) {
    return value * toMeters;
  }
}

/// Settings model untuk aplikasi
class AppSettings {
  final AreaUnit areaUnit;
  final LengthUnit lengthUnit;
  final Color pointColor;
  final Color lineColor;
  final Color polygonColor;
  final int pdfDpi;
  final double pointSize;
  final double lineWidth;
  final double polygonOpacity;

  AppSettings({
    this.areaUnit = AreaUnit.squareMeters,
    this.lengthUnit = LengthUnit.meters,
    this.pointColor = const Color(0xFF2196F3), // Blue
    this.lineColor = const Color(0xFF4CAF50), // Green
    this.polygonColor = const Color(0xFFFF9800), // Orange
    this.pdfDpi = 200,
    this.pointSize = 12.0,
    this.lineWidth = 3.0,
    this.polygonOpacity = 0.3,
  });

  // Default settings
  factory AppSettings.defaults() => AppSettings();

  // Copy with method
  AppSettings copyWith({
    AreaUnit? areaUnit,
    LengthUnit? lengthUnit,
    Color? pointColor,
    Color? lineColor,
    Color? polygonColor,
    int? pdfDpi,
    double? pointSize,
    double? lineWidth,
    double? polygonOpacity,
  }) {
    return AppSettings(
      areaUnit: areaUnit ?? this.areaUnit,
      lengthUnit: lengthUnit ?? this.lengthUnit,
      pointColor: pointColor ?? this.pointColor,
      lineColor: lineColor ?? this.lineColor,
      polygonColor: polygonColor ?? this.polygonColor,
      pdfDpi: pdfDpi ?? this.pdfDpi,
      pointSize: pointSize ?? this.pointSize,
      lineWidth: lineWidth ?? this.lineWidth,
      polygonOpacity: polygonOpacity ?? this.polygonOpacity,
    );
  }

  // To JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'areaUnit': areaUnit.name,
      'lengthUnit': lengthUnit.name,
      'pointColor': pointColor.value,
      'lineColor': lineColor.value,
      'polygonColor': polygonColor.value,
      'pdfDpi': pdfDpi,
      'pointSize': pointSize,
      'lineWidth': lineWidth,
      'polygonOpacity': polygonOpacity,
    };
  }

  // From JSON
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      areaUnit: AreaUnit.values.firstWhere(
        (e) => e.name == json['areaUnit'],
        orElse: () => AreaUnit.squareMeters,
      ),
      lengthUnit: LengthUnit.values.firstWhere(
        (e) => e.name == json['lengthUnit'],
        orElse: () => LengthUnit.meters,
      ),
      pointColor: Color(json['pointColor'] ?? 0xFF2196F3),
      lineColor: Color(json['lineColor'] ?? 0xFF4CAF50),
      polygonColor: Color(json['polygonColor'] ?? 0xFFFF9800),
      pdfDpi: json['pdfDpi'] ?? 200,
      pointSize: (json['pointSize'] ?? 12.0).toDouble(),
      lineWidth: (json['lineWidth'] ?? 3.0).toDouble(),
      polygonOpacity: (json['polygonOpacity'] ?? 0.3).toDouble(),
    );
  }

  // Format area dengan unit yang dipilih
  String formatArea(double areaInSquareMeters) {
    final converted = areaUnit.convert(areaInSquareMeters);
    return '${converted.toStringAsFixed(2)} ${areaUnit.symbol}';
  }

  // Format distance dengan unit yang dipilih
  String formatDistance(double distanceInMeters) {
    final converted = lengthUnit.convert(distanceInMeters);
    return '${converted.toStringAsFixed(2)} ${lengthUnit.symbol}';
  }
}
