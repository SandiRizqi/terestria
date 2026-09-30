import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/feature_style.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/layer_model.dart';

/// `GeoData.style` (SPEC §3): null = ikut default Settings; record tanpa style
/// punya JSON yang sama persis dengan sebelumnya.

const _style = LayerStyle(
  fillColor: Color(0xFFFF9800),
  fillOpacity: 0.3,
  strokeColor: Color(0xFFE65100),
  strokeWidth: 2,
  pointSize: 12,
);

GeoData _geo({LayerStyle? style}) => GeoData(
      id: 'g1',
      projectId: 'p1',
      formData: const {'Nama': 'Pohon 7'},
      points: [
        GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026, 9, 30),
      updatedAt: DateTime.utc(2026, 9, 30),
      style: style,
    );

Map<String, dynamic> _serverJson({Object? style, bool withKey = true}) => {
      'id': 'g1',
      'project_id': 'p1',
      'form_data': {'Nama': 'Pohon 7'},
      'points': [],
      'created_at': '2026-09-30T00:00:00Z',
      'updated_at': '2026-09-30T00:00:00Z',
      if (withKey) 'style': style,
    };

void main() {
  test('tanpa style: JSON lokal tanpa key style, dibaca kembali null', () {
    final json = _geo().toJson();
    expect(json.containsKey('style'), isFalse);
    expect(GeoData.fromJson(json).style, isNull);
  });

  test('dengan style: round-trip JSON lokal', () {
    expect(GeoData.fromJson(_geo(style: _style).toJson()).style, _style);
  });

  test('format server (snake_case): style dibaca; null/tanpa key → null', () {
    expect(GeoData.fromJson(_serverJson(style: featureStyleToJson(_style))).style,
        _style);
    expect(GeoData.fromJson(_serverJson(style: null)).style, isNull);
    expect(GeoData.fromJson(_serverJson(withKey: false)).style, isNull);
  });

  test('style rusak dari server → null, record tetap terbaca', () {
    final geo = GeoData.fromJson(_serverJson(style: {'fillColor': 'merah'}));
    expect(geo.id, 'g1');
    expect(geo.style, isNull);
  });

  test('copyWith: dipertahankan, diganti, dihapus', () {
    final styled = _geo(style: _style);
    expect(styled.copyWith(isSynced: true).style, _style);
    final other = _style.copyWith(pointSize: 18);
    expect(styled.copyWith(style: other).style, other);
    expect(styled.copyWith(clearStyle: true).style, isNull);
  });
}
