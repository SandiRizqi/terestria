import 'dart:typed_data';

import 'dbf_reader.dart';
import 'layer_importer.dart';

/// Ubah koordinat (x, y) shapefile → `[lon, lat]`.
typedef CoordTransform = List<double> Function(double x, double y);

/// Shapefile (`.shp` + `.dbf` opsional) → GeoJSON FeatureCollection.
///
/// Tipe: Point / MultiPoint / PolyLine / Polygon beserta varian Z & M (hanya
/// XY yang diambil). Polygon multi-ring dikelompokkan jadi Polygon /
/// MultiPolygon berdasar arah putaran (luar searah jarum jam, lubang
/// berlawanan). Record Null / terhapus di `.dbf` dilewati. [transform]
/// mereproyeksi tiap koordinat (default: apa adanya).
Map<String, dynamic> shapefileToGeoJson({
  required Uint8List shp,
  Uint8List? dbf,
  String? cpg,
  CoordTransform? transform,
}) {
  final geometries = readShpGeometries(shp, transform: transform);
  final rows = dbf == null ? null : readDbf(dbf, cpg: cpg);

  final features = <Map<String, dynamic>>[];
  for (var i = 0; i < geometries.length; i++) {
    final g = geometries[i];
    if (g == null) continue;
    Map<String, dynamic> props = {};
    if (rows != null && i < rows.length) {
      final row = rows[i];
      if (row == null) continue; // dihapus di .dbf
      props = row;
    }
    features.add({'type': 'Feature', 'properties': props, 'geometry': g});
  }
  return {'type': 'FeatureCollection', 'features': features};
}

/// Geometri GeoJSON per record `.shp` (null untuk Null shape / tipe tak
/// didukung seperti MultiPatch), urutan sama dengan record `.dbf`.
List<Map<String, dynamic>?> readShpGeometries(Uint8List shp,
    {CoordTransform? transform}) {
  if (shp.length < 100) {
    throw const LayerImportException('The .shp file is damaged (too short)');
  }
  final bd = ByteData.sublistView(shp);
  if (bd.getInt32(0, Endian.big) != 9994) {
    throw const LayerImportException('The .shp file is not valid');
  }
  final tf = transform ?? (double x, double y) => [x, y];

  final out = <Map<String, dynamic>?>[];
  var pos = 100;
  while (pos + 8 <= shp.length) {
    final len = bd.getInt32(pos + 4, Endian.big) * 2;
    final start = pos + 8;
    if (len < 4 || start + len > shp.length) {
      throw const LayerImportException(
          'The .shp file is truncated or damaged (incomplete record)');
    }
    out.add(_record(ByteData.sublistView(shp, start, start + len), tf));
    pos = start + len;
  }
  return out;
}

Map<String, dynamic>? _record(ByteData r, CoordTransform tf) {
  final type = r.getInt32(0, Endian.little);
  List<double> pt(int o) =>
      tf(r.getFloat64(o, Endian.little), r.getFloat64(o + 8, Endian.little));

  switch (type) {
    case 1:
    case 11:
    case 21:
      return {'type': 'Point', 'coordinates': pt(4)};
    case 8:
    case 18:
    case 28:
      final n = r.getInt32(36, Endian.little);
      return {
        'type': 'MultiPoint',
        'coordinates': [for (var i = 0; i < n; i++) pt(40 + i * 16)],
      };
    case 3:
    case 13:
    case 23:
    case 5:
    case 15:
    case 25:
      final numParts = r.getInt32(36, Endian.little);
      final numPoints = r.getInt32(40, Endian.little);
      final starts = [
        for (var i = 0; i < numParts; i++) r.getInt32(44 + i * 4, Endian.little)
      ];
      final ptBase = 44 + numParts * 4;
      final parts = <List<List<double>>>[];
      for (var p = 0; p < numParts; p++) {
        final end = p + 1 < numParts ? starts[p + 1] : numPoints;
        parts.add([for (var i = starts[p]; i < end; i++) pt(ptBase + i * 16)]);
      }
      return type % 10 == 3 ? _lines(parts) : _polygons(parts);
  }
  return null; // Null shape (0), MultiPatch (31), tipe tak dikenal
}

Map<String, dynamic>? _lines(List<List<List<double>>> parts) {
  final lines = parts.where((l) => l.length >= 2).toList();
  if (lines.isEmpty) return null;
  return lines.length == 1
      ? {'type': 'LineString', 'coordinates': lines.single}
      : {'type': 'MultiLineString', 'coordinates': lines};
}

Map<String, dynamic>? _polygons(List<List<List<double>>> rings) {
  final valid = rings.where((r) => r.length >= 4).toList();
  if (valid.isEmpty) return null;

  final outers = <List<List<List<double>>>>[];
  final holes = <List<List<double>>>[];
  for (final ring in valid) {
    if (_isClockwise(ring)) {
      outers.add([ring]);
    } else {
      holes.add(ring);
    }
  }
  if (outers.isEmpty) {
    // Penulis tak mengikuti aturan arah: jangan buang — tiap ring jadi polygon.
    return _polygonOrMulti([
      for (final h in holes) [h]
    ]);
  }
  for (final hole in holes) {
    final owner = outers.firstWhere(
      (poly) => _contains(poly.first, hole.first),
      orElse: () => const [],
    );
    if (owner.isEmpty) {
      outers.add([hole]); // lubang tanpa induk → polygon sendiri
    } else {
      owner.add(hole);
    }
  }
  return _polygonOrMulti(outers);
}

Map<String, dynamic> _polygonOrMulti(List<List<List<List<double>>>> polys) =>
    polys.length == 1
        ? {'type': 'Polygon', 'coordinates': polys.single}
        : {'type': 'MultiPolygon', 'coordinates': polys};

/// Rumus shoelace; > 0 = searah jarum jam (sumbu y ke atas).
bool _isClockwise(List<List<double>> ring) {
  var sum = 0.0;
  for (var i = 0; i + 1 < ring.length; i++) {
    sum += (ring[i + 1][0] - ring[i][0]) * (ring[i + 1][1] + ring[i][1]);
  }
  return sum > 0;
}

/// Ray casting: titik [p] di dalam [ring]?
bool _contains(List<List<double>> ring, List<double> p) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i][0], yi = ring[i][1];
    final xj = ring[j][0], yj = ring[j][1];
    if ((yi > p[1]) != (yj > p[1]) &&
        p[0] < (xj - xi) * (p[1] - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}
