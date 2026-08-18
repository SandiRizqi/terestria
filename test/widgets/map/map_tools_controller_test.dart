import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/models/settings/app_settings.dart';
import 'package:geoform_app/widgets/map/tools/map_tools_controller.dart';

void main() {
  const d = 100 / 111320.0; // ~100 m
  final settings = AppSettings.defaults();

  test('default mode none, not active', () {
    final c = MapToolsController();
    expect(c.mode, MapToolMode.none);
    expect(c.isActive, isFalse);
    expect(c.resultText(settings), '');
  });

  test('setMode activates and clears points; addPoint ignored when none', () {
    final c = MapToolsController();
    c.setMode(MapToolMode.distance);
    c.addPoint(const LatLng(0, 0));
    expect(c.points.length, 1);
    c.setMode(MapToolMode.none); // clears
    expect(c.points, isEmpty);
    c.addPoint(const LatLng(0, 0)); // ignored while none
    expect(c.points, isEmpty);
  });

  test('distance: length of two ~100 m segments', () {
    final c = MapToolsController()..setMode(MapToolMode.distance);
    c.addPoint(const LatLng(0, 0));
    c.addPoint(LatLng(0, d));
    c.addPoint(LatLng(d, d));
    expect(c.lengthMeters, closeTo(200, 3));
  });

  test('area: square ≈ 1 ha, perimeter ≈ 400 m', () {
    final c = MapToolsController()..setMode(MapToolMode.area);
    for (final p in [
      const LatLng(0, 0),
      LatLng(0, d),
      LatLng(d, d),
      LatLng(d, 0),
    ]) {
      c.addPoint(p);
    }
    expect(c.areaMeters, closeTo(10000, 50));
    expect(c.perimeterMeters, closeTo(400, 6));
  });

  test('bearing keeps only the last 2 points', () {
    final c = MapToolsController()..setMode(MapToolMode.bearing);
    c.addPoint(const LatLng(0, 0));
    c.addPoint(LatLng(0, d));
    c.addPoint(LatLng(d, 0)); // 3rd → oldest dropped
    expect(c.points.length, 2);
    expect(c.bearingDeg, isNotNull);
  });

  test('coordinate keeps only the last point', () {
    final c = MapToolsController()..setMode(MapToolMode.coordinate);
    c.addPoint(const LatLng(1, 2));
    c.addPoint(const LatLng(3, 4));
    expect(c.points.length, 1);
    expect(c.points.first.latitude, 3);
    expect(c.resultText(settings), contains('3'));
  });

  test('radius: center + edge → radius ≈ segment distance', () {
    final c = MapToolsController()..setMode(MapToolMode.radius);
    c.addPoint(const LatLng(0, 0));
    c.addPoint(LatLng(0, d));
    expect(c.radiusMeters, closeTo(100, 1.5));
  });

  test('undo removes last, clear empties, both notify', () {
    final c = MapToolsController()..setMode(MapToolMode.distance);
    var notifications = 0;
    c.addListener(() => notifications++);
    c.addPoint(const LatLng(0, 0));
    c.addPoint(LatLng(0, d));
    c.undo();
    expect(c.points.length, 1);
    c.clear();
    expect(c.points, isEmpty);
    expect(notifications, greaterThan(0));
  });
}
