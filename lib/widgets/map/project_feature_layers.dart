import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/feature_style.dart';
import '../../models/geo_data_model.dart';
import '../../models/layer_model.dart';
import '../../models/project_model.dart';
import '../../models/settings/app_settings.dart';
import '../../services/map/feature_hit_test.dart';

/// Gambar feature project di peta (peta project & layar navigasi) dengan style
/// masing-masing: style record bila ada, selain itu default dari Settings —
/// feature tanpa style tampil sama persis dengan render sebelum fitur style.

/// Style yang dipakai menggambar [data].
LayerStyle effectiveFeatureStyle(
        GeoData data, GeometryType type, AppSettings settings) =>
    data.style ?? defaultFeatureStyle(type, settings);

/// Diameter marker point dari `pointSize` (×2, dijepit 20–48 px agar tetap
/// mudah dilihat & diketuk) — sama dengan render sebelumnya.
double featurePointDiameter(LayerStyle style) =>
    (style.pointSize * 2).clamp(20.0, 48.0).toDouble();

List<LatLng> featureLatLngs(GeoData data) =>
    [for (final p in data.points) LatLng(p.latitude, p.longitude)];

/// Line: warna garis dengan opacity style (sama dengan layer line impor).
Polyline featurePolyline(GeoData data, LayerStyle style) => Polyline(
      points: featureLatLngs(data),
      color: style.strokeColor.withValues(alpha: style.fillOpacity),
      strokeWidth: style.strokeWidth,
    );

/// Polygon: isi warna isi + opacity; garis tepi ber-alpha 0.85 seperti render
/// sebelumnya.
Polygon featurePolygon(GeoData data, LayerStyle style) => Polygon(
      points: featureLatLngs(data),
      color: style.fillColor.withValues(alpha: style.fillOpacity),
      borderColor: style.strokeColor.withValues(alpha: 0.85),
      borderStrokeWidth: style.strokeWidth,
    );

/// Marker point: lingkaran warna style + ikon lokasi. Ukuran ikon =
/// diameter × [iconScale], dijepit [minIconSize]–[maxIconSize]. [onTap] null →
/// marker tidak menangkap tap sendiri.
Marker featurePointMarker(
  GeoData data,
  LayerStyle style, {
  double iconScale = 0.7,
  double minIconSize = 14,
  double maxIconSize = 26,
  VoidCallback? onTap,
}) {
  final diameter = featurePointDiameter(style);
  final first = data.points.first;
  Widget child = Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(
      color: style.fillColor.withValues(alpha: style.fillOpacity),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Icon(Icons.location_on,
        color: Colors.white,
        size: (diameter * iconScale).clamp(minIconSize, maxIconSize).toDouble()),
  );
  if (onTap != null) child = GestureDetector(onTap: onTap, child: child);
  return Marker(
    point: LatLng(first.latitude, first.longitude),
    width: diameter + 4,
    height: diameter + 4,
    child: child,
  );
}

/// Feature project yang kena tap di [tap] (select langsung, tanpa ikon info
/// di tengah feature). Aturan & urutan sesuai [hitFeatures]: yang kena
/// langsung didahulukan (radius marker dan tebal garis dari style feature);
/// point terdekat → line terdekat → polygon terkecil.
///
/// - [toScreen]: proyeksi kamera peta (LatLng → piksel layar, termasuk
///   rotasi) — tap & feature diproyeksikan dengan fungsi yang sama.
/// - [viewport]: hanya feature yang bbox-nya bersinggungan dengan layar yang
///   diuji (polygon besar yang di-zoom dari dalam tetap ikut).
/// - [features]: yang TAMPIL di peta — untuk point, pemanggil hanya memberi
///   marker yang tampil sendiri (bukan di dalam cluster; tap cluster sudah
///   ditangani cluster itu dengan zoom-in).
List<GeoData> projectFeaturesAtTap({
  required LatLng tap,
  required Iterable<GeoData> features,
  required GeometryType type,
  required AppSettings settings,
  required Offset Function(LatLng point) toScreen,
  LatLngBounds? viewport,
  double tolerance = defaultHitTolerance,
}) {
  final shapes = <HitShape<GeoData>>[];
  for (final data in features) {
    if (viewport != null && !_bboxIntersects(data, viewport)) continue;
    final style = effectiveFeatureStyle(data, type, settings);
    final shape = hitShapeFor(
      data,
      type,
      (p) => toScreen(LatLng(p.latitude, p.longitude)),
      pointRadius: featurePointDiameter(style) / 2,
      lineHalfWidth: style.strokeWidth / 2,
    );
    if (shape != null) shapes.add(shape);
  }
  return hitFeatures(toScreen(tap), shapes, tolerance: tolerance);
}

bool _bboxIntersects(GeoData data, LatLngBounds viewport) {
  if (data.points.isEmpty) return false;
  var minLat = double.infinity, maxLat = -double.infinity;
  var minLng = double.infinity, maxLng = -double.infinity;
  for (final p in data.points) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  return !(maxLat < viewport.south ||
      minLat > viewport.north ||
      maxLng < viewport.west ||
      minLng > viewport.east);
}
