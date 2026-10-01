import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/services/tracking/session_to_geodata.dart';

Project _proj(String id, GeometryType t) => Project(
      id: id,
      name: 'P$id',
      description: '',
      geometryType: t,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

GeoPoint _pt(double lon) =>
    GeoPoint(latitude: 0, longitude: lon, timestamp: DateTime(2026, 1, 1));

void main() {
  group('validateGeometry', () {
    test('line butuh ≥2 titik', () {
      expect(validateGeometry(GeometryType.line, 1).ok, isFalse);
      expect(validateGeometry(GeometryType.line, 2).ok, isTrue);
    });
    test('polygon butuh ≥3 titik', () {
      expect(validateGeometry(GeometryType.polygon, 2).ok, isFalse);
      expect(validateGeometry(GeometryType.polygon, 3).ok, isTrue);
    });
    test('point butuh ≥1 titik', () {
      expect(validateGeometry(GeometryType.point, 0).ok, isFalse);
      expect(validateGeometry(GeometryType.point, 1).ok, isTrue);
    });
    test('gagal membawa pesan error', () {
      expect(validateGeometry(GeometryType.polygon, 1).error, isNotNull);
    });
  });

  group('buildGeoData', () {
    test('memetakan project/points/formData/id/collectedBy', () {
      final now = DateTime(2026, 5, 1);
      final gd = buildGeoData(
        id: 'g1',
        project: _proj('a', GeometryType.line),
        points: [_pt(0), _pt(1)],
        formData: {'nama': 'jalan'},
        collectedBy: 'user1',
        now: now,
      );
      expect(gd, isA<GeoData>());
      expect(gd.id, 'g1');
      expect(gd.projectId, 'a');
      expect(gd.points.length, 2);
      expect(gd.formData['nama'], 'jalan');
      expect(gd.collectedBy, 'user1');
      expect(gd.createdAt, now);
      expect(gd.updatedAt, now);
      expect(gd.style, isNull); // tanpa style → ikut default
    });

    test('membawa style feature yang dipilih di form', () {
      const style = LayerStyle(
        fillColor: Color(0xFF9C27B0),
        fillOpacity: 0.6,
        strokeColor: Color(0xFF311B92),
        strokeWidth: 5,
        pointSize: 12,
      );
      final gd = buildGeoData(
        id: 'g2',
        project: _proj('a', GeometryType.line),
        points: [_pt(0), _pt(1)],
        formData: const {},
        style: style,
      );
      expect(gd.style, style);
    });
  });
}
