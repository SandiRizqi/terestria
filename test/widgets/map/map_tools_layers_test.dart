import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/widgets/map/tools/map_tools_controller.dart';
import 'package:geoform_app/widgets/map/tools/map_tools_layers.dart';

void main() {
  const d = 100 / 111320.0;

  test('none mode → no layers', () {
    expect(buildToolLayers(MapToolMode.none, const []), isEmpty);
  });

  test('distance (2 pts) → polyline + vertex markers', () {
    final l = buildToolLayers(
        MapToolMode.distance, [const LatLng(0, 0), LatLng(0, d)]);
    expect(l.whereType<PolylineLayer>().length, 1);
    expect(l.whereType<MarkerLayer>().length, 1);
  });

  test('area (≥3 pts) → polygon present', () {
    final l = buildToolLayers(MapToolMode.area,
        [const LatLng(0, 0), LatLng(0, d), LatLng(d, d)]);
    expect(l.whereType<PolygonLayer>().length, 1);
  });

  test('radius (2 pts) → circle present', () {
    final l = buildToolLayers(
        MapToolMode.radius, [const LatLng(0, 0), LatLng(0, d)]);
    expect(l.whereType<CircleLayer>().length, 1);
  });

  test('coordinate (1 pt) → marker only, no polyline', () {
    final l = buildToolLayers(MapToolMode.coordinate, [const LatLng(1, 2)]);
    expect(l.whereType<MarkerLayer>().length, 1);
    expect(l.whereType<PolylineLayer>(), isEmpty);
  });

  testWidgets('MapToolsLayer renders polyline inside a map after points added',
      (tester) async {
    final c = MapToolsController()..setMode(MapToolMode.distance);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 300,
          child: FlutterMap(
            options: const MapOptions(initialCenter: LatLng(0, 0), initialZoom: 5),
            children: [MapToolsLayer(controller: c)],
          ),
        ),
      ),
    ));
    c.addPoint(const LatLng(0, 0));
    c.addPoint(LatLng(0, d));
    await tester.pump();
    expect(find.byType(MapToolsLayer), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
  });
}
