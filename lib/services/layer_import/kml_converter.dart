import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'layer_importer.dart';
import 'xml_helpers.dart';
import 'zip_helpers.dart';

/// KML 2.x → GeoJSON FeatureCollection.
///
/// Semua `Placemark` (termasuk di dalam Folder/Document bersarang) dengan
/// geometri Point / LineString / LinearRing / Polygon (+ lubang
/// `innerBoundaryIs`) / MultiGeometry (campuran tipe dipecah jadi satu fitur
/// per bagian — peta tak merender GeometryCollection). Properti: `name`, `description`, dan
/// `ExtendedData` (`Data/value` & `SchemaData/SimpleData`).
Map<String, dynamic> kmlToGeoJson(String text) {
  final doc = parseXmlOrThrow(text, 'KML');
  final features = <Map<String, dynamic>>[];

  for (final pm in descendantsNamed(doc.rootElement, 'Placemark')) {
    final geometries = _placemarkGeometries(pm);
    if (geometries.isEmpty) continue;
    final props = _properties(pm);
    for (final geometry in geometries) {
      features.add({
        'type': 'Feature',
        'properties': Map<String, dynamic>.of(props),
        'geometry': geometry,
      });
    }
  }

  if (features.isEmpty) {
    throw const LayerImportException('The KML file has no placemarks with geometry');
  }
  return {'type': 'FeatureCollection', 'features': features};
}

/// KMZ = zip berisi `doc.kml` (atau `.kml` pertama, utamakan yang di root).
Map<String, dynamic> kmzToGeoJson(Uint8List bytes) {
  final files = decodeZipOrThrow(bytes, 'KMZ')
      .where((f) => f.name.toLowerCase().endsWith('.kml'))
      .toList()
    ..sort((a, b) => _kmlRank(a.name).compareTo(_kmlRank(b.name)));
  if (files.isEmpty) {
    throw const LayerImportException('The KMZ file does not contain a .kml file');
  }
  return kmlToGeoJson(
      utf8.decode(files.first.content, allowMalformed: true));
}

int _kmlRank(String name) {
  final n = name.toLowerCase();
  if (n == 'doc.kml') return 0;
  return n.contains('/') ? 2 : 1;
}

const _geometryNames = {
  'Point',
  'LineString',
  'LinearRing',
  'Polygon',
  'MultiGeometry',
};

/// Geometri pertama Placemark; MultiGeometry campuran → beberapa geometri.
List<Map<String, dynamic>> _placemarkGeometries(XmlElement pm) {
  for (final child in pm.childElements) {
    if (!_geometryNames.contains(child.name.local)) continue;
    if (child.name.local == 'MultiGeometry') {
      final parts = _multiParts(child);
      if (parts.isNotEmpty) return _combine(parts);
      continue;
    }
    final g = _geometry(child);
    if (g != null) return [g];
  }
  return const [];
}

/// Bagian-bagian MultiGeometry (MultiGeometry bersarang diratakan).
List<Map<String, dynamic>> _multiParts(XmlElement multi) => [
      for (final c in multi.childElements)
        if (c.name.local == 'MultiGeometry')
          ..._multiParts(c)
        else if (_geometryNames.contains(c.name.local))
          ...[_geometry(c)].whereType<Map<String, dynamic>>(),
    ];

Map<String, dynamic>? _geometry(XmlElement e) {
  switch (e.name.local) {
    case 'Point':
      final c = _coords(e);
      return c.isEmpty ? null : {'type': 'Point', 'coordinates': c.first};
    case 'LineString':
    case 'LinearRing':
      final c = _coords(e);
      return c.length < 2 ? null : {'type': 'LineString', 'coordinates': c};
    case 'Polygon':
      final rings = _polygonRings(e);
      return rings == null ? null : {'type': 'Polygon', 'coordinates': rings};
  }
  return null;
}

/// Bagian MultiGeometry → satu Multi* bila tipenya seragam, selain itu
/// dibiarkan terpisah (satu fitur per bagian).
List<Map<String, dynamic>> _combine(List<Map<String, dynamic>> parts) {
  if (parts.length == 1) return parts;
  final types = parts.map((p) => p['type']).toSet();
  if (types.length == 1 &&
      const {'Point', 'LineString', 'Polygon'}.contains(types.single)) {
    return [
      {
        'type': 'Multi${types.single}',
        'coordinates': [for (final p in parts) p['coordinates']],
      }
    ];
  }
  return parts;
}

List<List<List<double>>>? _polygonRings(XmlElement polygon) {
  List<List<double>>? ring(XmlElement boundary) {
    final lr = descendantsNamed(boundary, 'LinearRing').firstOrNull;
    if (lr == null) return null;
    final c = _coords(lr);
    if (c.isNotEmpty &&
        (c.first[0] != c.last[0] || c.first[1] != c.last[1])) {
      c.add(List.of(c.first));
    }
    return c.length >= 4 ? c : null;
  }

  final outerEl = childrenNamed(polygon, 'outerBoundaryIs').firstOrNull;
  final outer = outerEl == null ? null : ring(outerEl);
  if (outer == null) return null;
  return [
    outer,
    ...childrenNamed(polygon, 'innerBoundaryIs')
        .map(ring)
        .whereType<List<List<double>>>(),
  ];
}

/// Isi `<coordinates>` langsung milik [e]: tuple `lon,lat[,alt]` dipisah
/// spasi. Altitud dibuang; tuple rusak dilewati.
List<List<double>> _coords(XmlElement e) {
  final text = childText(e, 'coordinates');
  if (text == null) return [];
  final out = <List<double>>[];
  for (final tuple
      in text.replaceAll(RegExp(r'\s*,\s*'), ',').split(RegExp(r'\s+'))) {
    final parts = tuple.split(',');
    if (parts.length < 2) continue;
    final lon = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lon == null || lat == null || lat.abs() > 90 || lon.abs() > 180) {
      continue;
    }
    out.add([lon, lat]);
  }
  return out;
}

Map<String, dynamic> _properties(XmlElement pm) {
  final props = <String, dynamic>{};
  final name = childText(pm, 'name');
  final desc = childText(pm, 'description');
  if (name != null) props['name'] = name;
  if (desc != null) props['description'] = desc;
  for (final ext in childrenNamed(pm, 'ExtendedData')) {
    for (final data in descendantsNamed(ext, 'Data')) {
      final key = data.getAttribute('name');
      if (key == null || key.isEmpty) continue;
      props[key] = childText(data, 'value') ?? '';
    }
    for (final sd in descendantsNamed(ext, 'SimpleData')) {
      final key = sd.getAttribute('name');
      if (key == null || key.isEmpty) continue;
      props[key] = sd.innerText.trim();
    }
  }
  return props;
}
