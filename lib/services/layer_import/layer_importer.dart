import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../layer_service.dart';
import 'gpx_converter.dart';
import 'kml_converter.dart';

/// Format berkas yang bisa diimpor di halaman Layers. Semuanya dikonversi ke
/// GeoJSON FeatureCollection → sisa pipeline (simpan, style, render) sama.
enum LayerFormat { geojson, gpx, kml, kmz, zippedShapefile }

/// Batas ukuran berkas impor — berkas lebih besar hampir pasti membuat HP
/// kehabisan memori saat dikonversi.
const int kMaxLayerImportBytes = 100 * 1024 * 1024;

const String kSupportedLayerFormatsText =
    'GeoJSON (.geojson/.json), Shapefile ber-zip (.zip), GPX (.gpx), '
    'KML (.kml/.kmz/.xml)';

class LayerImportException implements Exception {
  final String message;
  const LayerImportException(this.message);
  @override
  String toString() => message;
}

/// Hasil konversi — sudah ringkas agar murah dikirim balik dari isolate.
class LayerImportResult {
  final LayerFormat format;
  final String defaultName;

  /// GeoJSON FeatureCollection ter-encode, siap disimpan apa adanya.
  final String geoJsonText;
  final String geometryType;
  final List<String> propertyKeys;
  final int featureCount;

  const LayerImportResult({
    required this.format,
    required this.defaultName,
    required this.geoJsonText,
    required this.geometryType,
    required this.propertyKeys,
    required this.featureCount,
  });
}

/// Tentukan format dari ekstensi; `.xml` diendus dari elemen root-nya
/// (`<gpx>` / `<kml>`). Format lain → [LayerImportException].
LayerFormat detectLayerFormat(String fileName, List<int> bytes) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'geojson':
    case 'json':
      return LayerFormat.geojson;
    case 'gpx':
      return LayerFormat.gpx;
    case 'kml':
      return LayerFormat.kml;
    case 'kmz':
      return LayerFormat.kmz;
    case 'zip':
      return LayerFormat.zippedShapefile;
    case 'xml':
      switch (xmlRootElementName(bytes)) {
        case 'gpx':
          return LayerFormat.gpx;
        case 'kml':
          return LayerFormat.kml;
      }
      throw const LayerImportException(
          'Berkas XML ini bukan GPX atau KML. Format yang didukung: '
          '$kSupportedLayerFormatsText');
  }
  throw const LayerImportException(
      'Format berkas tidak didukung. Format yang didukung: '
      '$kSupportedLayerFormatsText');
}

/// Nama lokal elemen root dokumen XML (tanpa prefix namespace), huruf kecil;
/// null bila tak ditemukan. Hanya membaca awal berkas.
String? xmlRootElementName(List<int> bytes) {
  final head = utf8.decode(
      bytes.length > 8192 ? bytes.sublist(0, 8192) : bytes,
      allowMalformed: true);
  final cleaned = head
      .replaceAll(RegExp(r'<!--[\s\S]*?(-->|$)'), '')
      .replaceAll(RegExp(r'<[?!][^>]*>?'), '');
  final m = RegExp(r'<(?:[A-Za-z_][\w.\-]*:)?([A-Za-z_][\w.\-]*)')
      .firstMatch(cleaned);
  return m?.group(1)?.toLowerCase();
}

/// Konversi isi berkas ke GeoJSON. Murni & sinkron — dijalankan di isolate
/// oleh [importLayerFile]. [shapefileName] memilih shapefile bila zip berisi
/// lebih dari satu.
LayerImportResult convertLayerBytes(String fileName, Uint8List bytes,
    {String? shapefileName}) {
  final format = detectLayerFormat(fileName, bytes);
  final Map<String, dynamic> fc;
  switch (format) {
    case LayerFormat.geojson:
      fc = _parseGeoJson(bytes);
    case LayerFormat.gpx:
      fc = gpxToGeoJson(_decodeText(bytes));
    case LayerFormat.kml:
      fc = kmlToGeoJson(_decodeText(bytes));
    case LayerFormat.kmz:
      fc = kmzToGeoJson(bytes);
    case LayerFormat.zippedShapefile:
      throw LayerImportException('Format ${format.name} belum didukung');
  }
  return _result(format, fileName, fc);
}

/// Baca berkas di [path] lalu konversi di isolate agar berkas besar tak
/// membekukan UI.
Future<LayerImportResult> importLayerFile(String path,
    {required String fileName, String? shapefileName}) {
  return compute(
      _importInIsolate, _ImportRequest(path, fileName, shapefileName));
}

class _ImportRequest {
  final String path;
  final String fileName;
  final String? shapefileName;
  const _ImportRequest(this.path, this.fileName, this.shapefileName);
}

LayerImportResult _importInIsolate(_ImportRequest req) {
  final file = File(req.path);
  final int size;
  try {
    size = file.lengthSync();
  } catch (e) {
    throw LayerImportException('Berkas tidak bisa dibaca: $e');
  }
  if (size > kMaxLayerImportBytes) {
    throw LayerImportException(
        'Berkas terlalu besar (${(size / 1048576).toStringAsFixed(0)} MB, '
        'maks ${kMaxLayerImportBytes ~/ 1048576} MB)');
  }
  return convertLayerBytes(req.fileName, file.readAsBytesSync(),
      shapefileName: req.shapefileName);
}

/// Teks UTF-8 (BOM dibuang; byte rusak diganti, bukan gagal total).
String _decodeText(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

String _baseName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  return base.trim().isEmpty ? 'Layer' : base.trim();
}

LayerImportResult _result(
    LayerFormat format, String fileName, Map<String, dynamic> fc) {
  final features = fc['features'] as List;
  if (features.isEmpty) {
    throw const LayerImportException('Berkas tidak berisi fitur/geometri');
  }
  return LayerImportResult(
    format: format,
    defaultName: _baseName(fileName),
    geoJsonText: jsonEncode(fc),
    geometryType: LayerService.detectGeometryType(fc),
    propertyKeys: LayerService.detectPropertyKeys(fc),
    featureCount: features.length,
  );
}

const _geometryTypes = {
  'Point',
  'MultiPoint',
  'LineString',
  'MultiLineString',
  'Polygon',
  'MultiPolygon',
  'GeometryCollection',
};

/// GeoJSON apa pun (FeatureCollection / Feature / geometri) → FeatureCollection.
Map<String, dynamic> _parseGeoJson(Uint8List bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } catch (e) {
    throw LayerImportException('GeoJSON tidak valid: $e');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const LayerImportException('GeoJSON tidak valid: bukan objek');
  }
  final type = decoded['type'];
  if (type == 'FeatureCollection' && decoded['features'] is List) {
    return decoded;
  }
  if (type == 'Feature') {
    return {
      'type': 'FeatureCollection',
      'features': [decoded],
    };
  }
  if (_geometryTypes.contains(type)) {
    return {
      'type': 'FeatureCollection',
      'features': [
        {'type': 'Feature', 'properties': <String, dynamic>{}, 'geometry': decoded},
      ],
    };
  }
  throw const LayerImportException(
      'GeoJSON tidak valid: tidak ada FeatureCollection/Feature/geometri');
}
