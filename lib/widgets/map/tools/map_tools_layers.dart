import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/app_theme.dart';
import 'map_tools_controller.dart';
import 'measure_math.dart';

// Warna alat ukur dari tema (amber/warning) — kontras di atas basemap satelit.
final Color _accent = AppTheme.warningColor;
final Color _fill = AppTheme.warningColor.withValues(alpha: 0.20);

/// Bangun daftar layer flutter_map untuk mode + titik saat ini. Fungsi murni
/// (tanpa state) sehingga mudah dites; konstruksi layer tidak butuh MapCamera.
List<Widget> buildToolLayers(MapToolMode mode, List<LatLng> pts) {
  final layers = <Widget>[];
  if (mode == MapToolMode.none || pts.isEmpty) return layers;

  // Polygon fill (area).
  if (mode == MapToolMode.area && pts.length >= 3) {
    layers.add(PolygonLayer(polygons: [
      Polygon(
        points: pts,
        color: _fill,
        borderColor: _accent,
        borderStrokeWidth: 2,
      ),
    ]));
  }

  // Radius circle.
  if (mode == MapToolMode.radius && pts.length >= 2) {
    final r = haversineMeters(
        pts[0].latitude, pts[0].longitude, pts[1].latitude, pts[1].longitude);
    layers.add(CircleLayer(circles: [
      CircleMarker(
        point: pts[0],
        radius: r,
        useRadiusInMeter: true,
        color: _fill,
        borderColor: _accent,
        borderStrokeWidth: 2,
      ),
    ]));
  }

  // Garis penghubung (distance / bearing / area outline / radius center-edge).
  final linePts = _linePoints(mode, pts);
  if (linePts.length >= 2) {
    layers.add(PolylineLayer(polylines: [
      Polyline(points: linePts, color: _accent, strokeWidth: 3),
    ]));
  }

  // Marker titik.
  layers.add(MarkerLayer(
    markers: [
      for (final p in pts)
        Marker(
          point: p,
          width: 14,
          height: 14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                  BorderSide(color: _accent, width: 3)),
            ),
          ),
        ),
    ],
  ));

  return layers;
}

List<LatLng> _linePoints(MapToolMode mode, List<LatLng> pts) {
  switch (mode) {
    case MapToolMode.distance:
      return pts;
    case MapToolMode.area:
      return pts.length >= 3 ? [...pts, pts.first] : pts;
    case MapToolMode.bearing:
    case MapToolMode.radius:
      return pts.take(2).toList();
    case MapToolMode.coordinate:
    case MapToolMode.none:
      return const [];
  }
}

/// Widget layer yang mendengarkan [controller] dan menampilkan layer alat ukur
/// di dalam FlutterMap. Sertakan sebagai salah satu `children` FlutterMap.
class MapToolsLayer extends StatelessWidget {
  final MapToolsController controller;
  const MapToolsLayer({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Stack(
        children: buildToolLayers(controller.mode, controller.points),
      ),
    );
  }
}
