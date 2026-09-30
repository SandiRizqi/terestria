import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/settings/app_settings.dart';
import 'package:geoform_app/widgets/map/project_feature_layers.dart';

/// Tap langsung di peta project (T11): feature mana yang kena tap —
/// culling per viewport (bbox), point bertumpuk ikut semua, radius marker
/// point dari style feature.

final _settings = AppSettings(pointSize: 12);

// Proyeksi linear sederhana: 1 derajat = 1000 px.
Offset _toScreen(LatLng p) => Offset(p.longitude * 1000, p.latitude * 1000);

GeoData _square(String id, double lat0, double lng0, double size) => GeoData(
      id: id,
      projectId: 'p',
      formData: const {},
      points: [
        GeoPoint(latitude: lat0, longitude: lng0, timestamp: DateTime.utc(2026)),
        GeoPoint(latitude: lat0, longitude: lng0 + size, timestamp: DateTime.utc(2026)),
        GeoPoint(latitude: lat0 + size, longitude: lng0 + size, timestamp: DateTime.utc(2026)),
        GeoPoint(latitude: lat0 + size, longitude: lng0, timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

GeoData _point(String id, double lat, double lng, {LayerStyle? style}) => GeoData(
      id: id,
      projectId: 'p',
      formData: const {},
      points: [GeoPoint(latitude: lat, longitude: lng, timestamp: DateTime.utc(2026))],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      style: style,
    );

final _viewport = LatLngBounds(const LatLng(-0.2, -0.2), const LatLng(0.2, 0.2));

List<String> _ids(List<GeoData> hits) => [for (final h in hits) h.id];

void main() {
  test('polygon yang memuat tap → kena; bertumpuk → terkecil dulu', () {
    final hits = projectFeaturesAtTap(
      tap: const LatLng(0.05, 0.05),
      features: [_square('besar', -1, -1, 2), _square('kecil', 0, 0, 0.1)],
      type: GeometryType.polygon,
      settings: _settings,
      toScreen: _toScreen,
      viewport: _viewport,
    );
    // 'besar' memuat seluruh viewport (semua titiknya di luar layar) → tetap
    // ikut, karena bbox-nya bersinggungan dengan viewport.
    expect(_ids(hits), ['kecil', 'besar']);
  });

  test('feature di luar viewport tidak ikut diuji', () {
    final far = _square('jauh', 5, 5, 0.1);
    expect(
        projectFeaturesAtTap(
          tap: const LatLng(5.05, 5.05),
          features: [far],
          type: GeometryType.polygon,
          settings: _settings,
          toScreen: _toScreen,
          viewport: _viewport,
        ),
        isEmpty);
    expect(
        _ids(projectFeaturesAtTap(
          tap: const LatLng(5.05, 5.05),
          features: [far],
          type: GeometryType.polygon,
          settings: _settings,
          toScreen: _toScreen,
        )),
        ['jauh']);
  });

  test('point bertumpuk → semua ikut, terdekat dulu', () {
    final hits = projectFeaturesAtTap(
      tap: const LatLng(0, 0.001),
      features: [_point('jauh', 0, 0.008), _point('dekat', 0, 0)],
      type: GeometryType.point,
      settings: _settings,
      toScreen: _toScreen,
    );
    expect(_ids(hits), ['dekat', 'jauh']);
  });

  test('radius marker point mengikuti ukuran style feature', () {
    const big = LayerStyle(
      fillColor: Color(0xFF000000),
      fillOpacity: 1,
      strokeColor: Color(0xFF000000),
      strokeWidth: 2,
      pointSize: 20, // diameter 40 → radius 20
    );
    // Tap 40 px dari titik: default (diameter 24 → radius 12, +24 = 36) luput;
    // style besar (radius 20, +24 = 44) kena.
    List<GeoData> at(GeoData g) => projectFeaturesAtTap(
          tap: const LatLng(0, 0.04),
          features: [g],
          type: GeometryType.point,
          settings: _settings,
          toScreen: _toScreen,
        );
    expect(at(_point('default', 0, 0)), isEmpty);
    expect(_ids(at(_point('besar', 0, 0, style: big))), ['besar']);
  });
}
