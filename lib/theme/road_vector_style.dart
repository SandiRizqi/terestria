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

  // ─── Palet warna (mengikuti style MapLibre TAP: source-layer `road`) ──────
  static const Color _major = Color(0xFFE65100); // primary (& motorway/trunk)
  static const Color _secondary = Color(0xFFF57C00); // secondary
  static const Color _tertiary = Color(0xFFFBC02D); // tertiary
  static const Color _residential = Color(0xFFBDBDBD); // residential
  static const Color _service = Color(0xFF9E9E9E); // service
  static const Color _track = Color(0xFFA1887F); // track
  static const Color _other = Color(0xFF999999); // fallback (jalan-major other)

  /// Gaya default untuk kelas jalan yang tak punya entri khusus.
  static const RoadStyle defaultStyle = RoadStyle(_other, 1.2);

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

  /// Peta kelas → gaya. Warna dari palet TAP; ketebalan menurun dari arteri ke
  /// jalan kecil (majors jauh lebih tebal, seperti interpolasi width di style).
  static const Map<String, RoadStyle> _styles = {
    // Majors — oranye TAP (#E65100). motorway/trunk disamakan dgn primary.
    'motorway': RoadStyle(_major, 3.2),
    'motorway_link': RoadStyle(_major, 2.2),
    'trunk': RoadStyle(_major, 3.0),
    'trunk_link': RoadStyle(_major, 2.0),
    'primary': RoadStyle(_major, 3.0),
    'primary_link': RoadStyle(_major, 2.0),
    'secondary': RoadStyle(_secondary, 2.6),
    'secondary_link': RoadStyle(_secondary, 1.8),
    'tertiary': RoadStyle(_tertiary, 2.0),
    'tertiary_link': RoadStyle(_tertiary, 1.6),
    'unclassified': RoadStyle(_residential, 1.6),
    'residential': RoadStyle(_residential, 1.6),
    'living_street': RoadStyle(_residential, 1.4),
    'road': RoadStyle(_residential, 1.5),
    'service': RoadStyle(_service, 1.3),
    'track': RoadStyle(_track, 1.5),
  };

  /// Kembalikan gaya garis untuk kelas [highway], atau `null` bila kelas ini
  /// tidak digambar (pejalan kaki / null / kosong).
  static RoadStyle? forHighway(String? highway) {
    if (highway == null || highway.isEmpty) return null;
    if (_skip.contains(highway)) return null;
    return _styles[highway] ?? defaultStyle;
  }
}
