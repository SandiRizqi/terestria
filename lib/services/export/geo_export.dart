import 'dart:convert';

import '../../models/form_field_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';

/// Hasil ekspor GeoJSON: FeatureCollection + id record yang DILEWATI karena
/// geometrinya tak valid (tanpa titik / titik kurang) — dulu diekspor ke
/// `[0,0]` ("Null Island") atau sebagai LineString/Polygon rusak.
class GeoJsonExport {
  final Map<String, dynamic> collection;
  final int featureCount;
  final List<String> skippedIds;

  const GeoJsonExport({
    required this.collection,
    required this.featureCount,
    required this.skippedIds,
  });

  String encode({bool pretty = true}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(collection)
      : jsonEncode(collection);
}

/// Builder ekspor murni (tanpa UI/IO) agar bisa diuji & dijalankan di isolate.
class GeoExport {
  GeoExport._();

  /// Koordinat valid: angka hingga & dalam rentang WGS84.
  static bool _validPoint(GeoPoint p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180;

  /// Posisi GeoJSON `[lon, lat(, alt)]` dengan dimensi SERAGAM: altitude hanya
  /// disertakan bila SEMUA titik memilikinya (dulu 2D/3D campur dalam satu
  /// ring → ditolak sebagian GIS). Titik tak valid dibuang.
  static List<List<double>> positions(List<GeoPoint> points) {
    final valid = points.where(_validPoint).toList();
    final withAlt = valid.isNotEmpty &&
        valid.every((p) => p.altitude != null && p.altitude!.isFinite);
    return [
      for (final p in valid)
        [p.longitude, p.latitude, if (withAlt) p.altitude!],
    ];
  }

  static bool _samePosition(List<double> a, List<double> b) =>
      a.length >= 2 && b.length >= 2 && a[0] == b[0] && a[1] == b[1];

  /// Luas bertanda (shoelace, bidang lon/lat): positif = berlawanan jarum jam.
  static double _signedArea(List<List<double>> ring) {
    var sum = 0.0;
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      sum += a[0] * b[1] - b[0] * a[1];
    }
    return sum / 2;
  }

  /// Geometri GeoJSON untuk [type], atau `null` bila titiknya tak cukup untuk
  /// geometri yang valid (Point ≥1, LineString ≥2 posisi berbeda, Polygon ≥3).
  static Map<String, dynamic>? geometryFor(
      GeometryType type, List<GeoPoint> points) {
    final pos = positions(points);
    switch (type) {
      case GeometryType.point:
        if (pos.isEmpty) return null;
        return {'type': 'Point', 'coordinates': pos.first};

      case GeometryType.line:
        final distinct = <String>{for (final p in pos) '${p[0]},${p[1]}'};
        if (distinct.length < 2) return null;
        return {'type': 'LineString', 'coordinates': pos};

      case GeometryType.polygon:
        final ring = List<List<double>>.of(pos);
        // Titik penutup yang sudah ada dibandingkan NILAINYA (dulu `!=` pada
        // List selalu true → vertex penutup ganda).
        while (ring.length > 1 && _samePosition(ring.first, ring.last)) {
          ring.removeLast();
        }
        final distinct = <String>{for (final p in ring) '${p[0]},${p[1]}'};
        if (distinct.length < 3) return null;
        // RFC 7946: ring luar berlawanan arah jarum jam.
        final oriented =
            _signedArea(ring) < 0 ? ring.reversed.toList() : ring;
        return {
          'type': 'Polygon',
          'coordinates': [
            [...oriented, oriented.first],
          ],
        };
    }
  }

  /// Nilai yang aman di-encode JSON: NaN/∞ → null, DateTime → ISO UTC,
  /// objek lain → string (dulu satu nilai aneh menggagalkan seluruh ekspor).
  static Object? jsonSafe(Object? value) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) return value.isFinite ? value : null;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return {
        for (final e in value.entries) e.key.toString(): jsonSafe(e.value),
      };
    }
    if (value is Iterable) return [for (final v in value) jsonSafe(v)];
    return value.toString();
  }

  static double? _worstAccuracy(List<GeoPoint> points) {
    double? worst;
    for (final p in points) {
      final a = p.accuracy;
      if (a == null || !a.isFinite) continue;
      if (worst == null || a > worst) worst = a;
    }
    return worst;
  }

  /// FeatureCollection untuk [records] (urutan dipertahankan).
  static GeoJsonExport geoJson(Project project, List<GeoData> records) {
    final features = <Map<String, dynamic>>[];
    final skipped = <String>[];

    for (final d in records) {
      final geometry = geometryFor(project.geometryType, d.points);
      if (geometry == null) {
        skipped.add(d.id);
        continue;
      }
      final first = d.points.isNotEmpty ? d.points.first : null;
      final accuracy = project.geometryType == GeometryType.point
          ? first?.accuracy
          : _worstAccuracy(d.points);
      final properties = <String, dynamic>{
        'id': d.id,
        'createdAt': d.createdAt.toUtc().toIso8601String(),
        'updatedAt': d.updatedAt.toUtc().toIso8601String(),
        'isSynced': d.isSynced,
        if (d.collectedBy != null && d.collectedBy!.isNotEmpty)
          'collectedBy': d.collectedBy,
        'pointCount': d.points.length,
        if (accuracy != null && accuracy.isFinite) 'gpsAccuracyM': accuracy,
        if (project.geometryType == GeometryType.point &&
            first?.fixQuality != null)
          'fixQuality': first!.fixQuality,
      };
      // Atribut form (nama field = label) — menimpa metadata bila labelnya
      // sama, seperti perilaku sebelumnya.
      final form = jsonSafe(d.formData);
      if (form is Map<String, dynamic>) properties.addAll(form);

      features.add({
        'type': 'Feature',
        'id': d.id,
        'geometry': geometry,
        'properties': properties,
      });
    }

    return GeoJsonExport(
      collection: {
        'type': 'FeatureCollection',
        'name': project.name,
        'crs': {
          'type': 'name',
          'properties': {'name': 'urn:ogc:def:crs:OGC:1.3:CRS84'},
        },
        'features': features,
      },
      featureCount: features.length,
      skippedIds: skipped,
    );
  }

  /// Escape satu sel CSV. Teks yang diawali `= + - @` (bukan angka) diberi
  /// awalan `'` agar Excel/Sheets tak mengeksekusinya sebagai formula.
  static String csvEscape(Object? value) {
    if (value == null) return '';
    var str = value is double && !value.isFinite ? '' : value.toString();
    if (value is String &&
        str.isNotEmpty &&
        '=+-@\t\r'.contains(str[0]) &&
        num.tryParse(str) == null) {
      str = "'$str";
    }
    if (str.contains(',') ||
        str.contains('"') ||
        str.contains('\n') ||
        str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  /// CSV tabular: satu baris per record (koordinat = titik pertama).
  ///
  /// Kolom: id, latitude, longitude, altitude, point_count, created_at,
  /// collected_by, [field non-foto…], [`<foto>_photo_count`…].
  static String csv(Project project, List<GeoData> records) {
    final dynamicFields =
        project.formFields.where((f) => f.type != FieldType.photo).toList();
    final photoFields =
        project.formFields.where((f) => f.type == FieldType.photo).toList();

    final buffer = StringBuffer()
      ..writeln([
        'id',
        'latitude',
        'longitude',
        'altitude',
        'point_count',
        'created_at',
        'collected_by',
        ...dynamicFields.map((f) => csvEscape(f.label)),
        ...photoFields.map((f) => csvEscape('${f.label}_photo_count')),
      ].join(','));

    for (final d in records) {
      final valid = d.points.where(_validPoint);
      final first = valid.isEmpty ? null : valid.first;
      final row = <String>[
        csvEscape(d.id),
        csvEscape(first?.latitude),
        csvEscape(first?.longitude),
        csvEscape(first?.altitude),
        csvEscape(d.points.length),
        csvEscape(d.createdAt.toIso8601String()),
        csvEscape(d.collectedBy ?? ''),
        ...dynamicFields.map((f) {
          final val = d.formData[f.label];
          if (f.type == FieldType.checkbox) {
            return csvEscape(
                val == true || val.toString().toLowerCase() == 'true'
                    ? 'Yes'
                    : 'No');
          }
          if (val is List) return csvEscape(val.join('; '));
          return csvEscape(val);
        }),
        ...photoFields.map((f) {
          final val = d.formData[f.label];
          if (val is List) return csvEscape(val.length);
          if (val != null && val.toString().isNotEmpty) return '1';
          return '0';
        }),
      ];
      buffer.writeln(row.join(','));
    }
    return buffer.toString();
  }
}
