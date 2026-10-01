import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/settings/app_settings.dart';
import 'package:geoform_app/widgets/map/project_feature_layers.dart';

/// Gambar feature project dengan style masing-masing (T5). Feature TANPA
/// style harus tampil sama persis dengan render lama (warna/ukuran Settings).

final _settings = AppSettings(
  pointColor: const Color(0xFF2196F3),
  lineColor: const Color(0xFF4CAF50),
  polygonColor: const Color(0xFFFF9800),
  pointSize: 12,
  lineWidth: 3,
  polygonOpacity: 0.3,
);

const _custom = LayerStyle(
  fillColor: Color(0xFF9C27B0),
  fillOpacity: 0.6,
  strokeColor: Color(0xFF311B92),
  strokeWidth: 6,
  pointSize: 18,
);

GeoData _geo({LayerStyle? style, int points = 3}) => GeoData(
      id: 'g1',
      projectId: 'p1',
      formData: const {},
      points: [
        for (var i = 0; i < points; i++)
          GeoPoint(
              latitude: -6.2 + i * 0.001,
              longitude: 106.8 + (i.isOdd ? 0.001 : 0),
              timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      style: style,
    );

Future<BoxDecoration> _markerDecoration(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Center(child: child)));
  final box = tester.widget<Container>(find.byType(Container).first);
  return box.decoration! as BoxDecoration;
}

void main() {
  group('kotak batas feature ↔ area peta (culling tampilan = hit-test)', () {
    // Area peta sekitar (0, 0), selebar ±0,01°.
    final viewport =
        LatLngBounds(const LatLng(-0.01, -0.01), const LatLng(0.01, 0.01));
    GeoData shape(List<(double, double)> latLngs) => GeoData(
          id: 's',
          projectId: 'p',
          formData: const {},
          points: [
            for (final (lat, lng) in latLngs)
              GeoPoint(latitude: lat, longitude: lng, timestamp: DateTime.utc(2026)),
          ],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );

    test('kotak batas dari titik-titik feature; tanpa titik → null', () {
      final b = featureBounds(shape([(1, 2), (-3, 5), (0, -1)]))!;
      expect((b.south, b.west, b.north, b.east), (-3.0, -1.0, 1.0, 5.0));
      expect(featureBounds(shape([])), isNull);
    });

    test('polygon besar yang menutupi seluruh area (semua titik sudut di '
        'luar) tetap bersinggungan', () {
      final big = shape([(-1, -1), (-1, 1), (1, 1), (1, -1)]);
      expect(big.points.any((p) => viewport.contains(LatLng(p.latitude, p.longitude))),
          isFalse);
      expect(boundsIntersect(featureBounds(big)!, viewport), isTrue);
    });

    test('line panjang yang melintasi area dengan kedua ujung jauh tetap '
        'bersinggungan', () {
      expect(boundsIntersect(featureBounds(shape([(0, -1), (0, 1)]))!, viewport),
          isTrue);
    });

    test('feature yang sepenuhnya di luar area tidak bersinggungan', () {
      expect(boundsIntersect(featureBounds(shape([(1, 1), (1.1, 1.1)]))!, viewport),
          isFalse);
      expect(boundsIntersect(featureBounds(shape([(0, 0.02), (0.005, 0.03)]))!, viewport),
          isFalse);
    });
  });

  group('tanpa style — sama dengan render lama', () {
    test('line: warna line α 0.8, tebal line', () {
      final style = effectiveFeatureStyle(_geo(), GeometryType.line, _settings);
      final line = featurePolyline(_geo(), style);
      expect(line.color, _settings.lineColor.withValues(alpha: 0.8));
      expect(line.strokeWidth, _settings.lineWidth);
      expect(line.points, hasLength(3));
    });

    test('polygon: isi warna polygon α polygonOpacity, tepi α 0.85, tebal line',
        () {
      final style =
          effectiveFeatureStyle(_geo(), GeometryType.polygon, _settings);
      final poly = featurePolygon(_geo(), style);
      expect(poly.color, _settings.polygonColor.withValues(alpha: 0.3));
      expect(poly.borderColor, _settings.polygonColor.withValues(alpha: 0.85));
      expect(poly.borderStrokeWidth, _settings.lineWidth);
    });

    testWidgets('point: diameter (pointSize × 2, 20–48) & warna point',
        (tester) async {
      final style = effectiveFeatureStyle(_geo(), GeometryType.point, _settings);
      final marker = featurePointMarker(_geo(points: 1), style);
      expect(marker.width, 24 + 4);
      final deco = await _markerDecoration(tester, marker.child);
      expect(deco.color, _settings.pointColor);
    });
  });

  group('dengan style record', () {
    test('line & polygon memakai warna, opacity, dan tebal milik record', () {
      final geo = _geo(style: _custom);
      final line =
          featurePolyline(geo, effectiveFeatureStyle(geo, GeometryType.line, _settings));
      expect(line.color, _custom.strokeColor.withValues(alpha: 0.6));
      expect(line.strokeWidth, 6);

      final poly = featurePolygon(
          geo, effectiveFeatureStyle(geo, GeometryType.polygon, _settings));
      expect(poly.color, _custom.fillColor.withValues(alpha: 0.6));
      expect(poly.borderColor, _custom.strokeColor.withValues(alpha: 0.85));
      expect(poly.borderStrokeWidth, 6);
    });

    testWidgets('point memakai warna, opacity, dan ukuran milik record',
        (tester) async {
      final geo = _geo(style: _custom, points: 1);
      final marker = featurePointMarker(
          geo, effectiveFeatureStyle(geo, GeometryType.point, _settings));
      expect(marker.width, 36 + 4);
      final deco = await _markerDecoration(tester, marker.child);
      expect(deco.color, _custom.fillColor.withValues(alpha: 0.6));
    });
  });

  testWidgets('marker point hanya bisa diketuk bila diberi onTap', (tester) async {
    final style = effectiveFeatureStyle(_geo(), GeometryType.point, _settings);
    var taps = 0;
    final tappable = featurePointMarker(_geo(points: 1), style, onTap: () => taps++);
    await tester.pumpWidget(MaterialApp(home: Center(child: tappable.child)));
    await tester.tap(find.byType(GestureDetector));
    expect(taps, 1);

    final plain = featurePointMarker(_geo(points: 1), style);
    await tester.pumpWidget(MaterialApp(home: Center(child: plain.child)));
    expect(find.byType(GestureDetector), findsNothing);
  });
}
