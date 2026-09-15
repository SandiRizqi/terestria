import 'package:flutter/material.dart';

/// Gaya garis satu kelas jalan pada basemap raster jaringan jalan.
///
/// [strokeWidth] adalah lebar acuan (px) pada zoom render; provider tile boleh
/// menyesuaikan sedikit terhadap zoom bila perlu. Warna diambil dari palet
/// Material bertingkat (bukan hex sebar) agar konsisten & mudah disetel.
class RoadStyle {
  final Color color;
  final double strokeWidth;
  const RoadStyle(this.color, this.strokeWidth);
}

/// Pemetaan nilai tag OSM `highway` → [RoadStyle].
///
/// - Kelas kendaraan (motorway … track) → warna & ketebalan berjenjang.
/// - Kelas non-jalan (pejalan kaki: footway/path/steps/cycleway/…) → `null`
///   (dilewati; basemap ini fokus "jalan", bukan trotoar).
/// - Kelas dikenal-tapi-tak-terpetakan (mis. `busway`) → [defaultStyle].
/// - `null` / kosong → `null`.
class RoadVectorStyle {
  RoadVectorStyle._();

  /// Gaya default untuk kelas jalan yang tak punya entri khusus.
  static final RoadStyle defaultStyle = RoadStyle(Colors.grey.shade500, 1.0);

  /// Kelas jalan yang SENGAJA tidak digambar (khusus pejalan kaki / non-jalan).
  static const Set<String> _skip = {
    'footway',
    'path',
    'steps',
    'cycleway',
    'pedestrian',
    'bridleway',
    'corridor',
    'construction',
    'proposed',
    'raceway',
    'bus_guideway',
    'elevator',
    'platform',
  };

  /// Peta kelas → gaya. Ketebalan menurun dari jalan arteri ke jalan kecil.
  static final Map<String, RoadStyle> _styles = {
    'motorway': RoadStyle(Colors.orange.shade700, 2.4),
    'motorway_link': RoadStyle(Colors.orange.shade700, 1.8),
    'trunk': RoadStyle(Colors.orange.shade600, 2.2),
    'trunk_link': RoadStyle(Colors.orange.shade600, 1.7),
    'primary': RoadStyle(Colors.orange.shade400, 2.0),
    'primary_link': RoadStyle(Colors.orange.shade400, 1.5),
    'secondary': RoadStyle(Colors.amber.shade600, 1.7),
    'secondary_link': RoadStyle(Colors.amber.shade600, 1.3),
    'tertiary': RoadStyle(Colors.grey.shade600, 1.4),
    'tertiary_link': RoadStyle(Colors.grey.shade600, 1.2),
    'unclassified': RoadStyle(Colors.grey.shade500, 1.1),
    'residential': RoadStyle(Colors.grey.shade500, 1.1),
    'living_street': RoadStyle(Colors.grey.shade400, 1.0),
    'road': RoadStyle(Colors.grey.shade500, 1.0),
    'service': RoadStyle(Colors.grey.shade400, 0.9),
    'track': RoadStyle(Colors.brown.shade400, 1.0),
  };

  /// Kembalikan gaya garis untuk kelas [highway], atau `null` bila kelas ini
  /// tidak digambar (pejalan kaki / null / kosong).
  static RoadStyle? forHighway(String? highway) {
    if (highway == null || highway.isEmpty) return null;
    if (_skip.contains(highway)) return null;
    return _styles[highway] ?? defaultStyle;
  }
}
