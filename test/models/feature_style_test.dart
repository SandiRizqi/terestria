import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/feature_style.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/settings/app_settings.dart';

/// Style per feature (SPEC §3): JSON kontrak dengan backend — warna `#RRGGBB`,
/// opacity terpisah, rentang sama dengan slider editor Layers.

const _style = LayerStyle(
  fillColor: Color(0xFFFF9800),
  fillOpacity: 0.3,
  strokeColor: Color(0xFFE65100),
  strokeWidth: 2,
  pointSize: 12,
);

void main() {
  group('featureStyleToJson / featureStyleFromJson', () {
    test('format kontrak: hex huruf besar tanpa alpha + angka', () {
      expect(featureStyleToJson(_style), {
        'fillColor': '#FF9800',
        'fillOpacity': 0.3,
        'strokeColor': '#E65100',
        'strokeWidth': 2.0,
        'pointSize': 12.0,
      });
    });

    test('round-trip tidak berubah', () {
      expect(featureStyleFromJson(featureStyleToJson(_style)), _style);
    });

    test('null ↔ null (ikut default)', () {
      expect(featureStyleToJson(null), isNull);
      expect(featureStyleFromJson(null), isNull);
    });

    test('hex huruf kecil diterima; key asing diabaikan', () {
      final json = {
        ...featureStyleToJson(_style)!,
        'fillColor': '#ff9800',
        'dash': 'solid',
      };
      expect(featureStyleFromJson(json), _style);
    });

    test('tidak valid → null', () {
      final ok = featureStyleToJson(_style)!;
      final bad = <Object?>[
        'merah',
        5,
        <dynamic>[],
        {...ok}..remove('pointSize'),
        {...ok, 'fillColor': '#FFF'},
        {...ok, 'strokeColor': 0xFFE65100},
        {...ok, 'fillOpacity': '0.3'},
        {...ok, 'strokeWidth': double.nan},
      ];
      for (final value in bad) {
        expect(featureStyleFromJson(value), isNull, reason: '$value');
      }
    });

    test('angka di luar rentang di-clamp, saat dibaca maupun dikirim', () {
      final read = featureStyleFromJson({
        ...featureStyleToJson(_style)!,
        'fillOpacity': 0,
        'strokeWidth': 99,
        'pointSize': 1,
      })!;
      expect(read.fillOpacity, 0.05);
      expect(read.strokeWidth, 10);
      expect(read.pointSize, 10);

      final sent =
          featureStyleToJson(_style.copyWith(fillOpacity: 2, pointSize: 50))!;
      expect(sent['fillOpacity'], 1.0);
      expect(sent['pointSize'], 24.0);
    });

    test('ukuran point 10–24 = diameter marker 20–48 dp; semua nilai Settings '
        '(8–24) muat', () {
      expect((featureMinPointSize, featureMaxPointSize), (10.0, 24.0));
      LayerStyle fromSettings(double size) => clampFeatureStyle(
          defaultFeatureStyle(
              GeometryType.point, AppSettings(pointSize: size)));
      // Settings maksimum: mengganti warna saja tidak mengecilkan point.
      expect(fromSettings(24).pointSize, 24);
      // Settings 8 tampil 20 dp, sama dengan 10.
      expect(fromSettings(8).pointSize, 10);
    });

    test('warna ber-alpha: alpha dibuang (opacity terpisah)', () {
      final json = featureStyleToJson(
          _style.copyWith(fillColor: const Color(0x80FF9800)))!;
      expect(json['fillColor'], '#FF9800');
    });
  });

  group('defaultFeatureStyle — sama dengan render default sekarang', () {
    final settings = AppSettings(
      pointColor: const Color(0xFF123456),
      lineColor: const Color(0xFF00AA00),
      polygonColor: const Color(0xFFFF9800),
      pointSize: 10,
      lineWidth: 4,
      polygonOpacity: 0.4,
    );

    test('point: warna point, opacity penuh, ukuran point', () {
      final s = defaultFeatureStyle(GeometryType.point, settings);
      expect(s.fillColor, settings.pointColor);
      expect(s.fillOpacity, 1.0);
      expect(s.pointSize, 10);
    });

    test('line: warna line, opacity 0.8, tebal line', () {
      final s = defaultFeatureStyle(GeometryType.line, settings);
      expect(s.strokeColor, settings.lineColor);
      expect(s.fillOpacity, 0.8);
      expect(s.strokeWidth, 4);
    });

    test('polygon: isi warna polygon + opacity polygon, garis tepi warna '
        'polygon, tebal line', () {
      final s = defaultFeatureStyle(GeometryType.polygon, settings);
      expect(s.fillColor, settings.polygonColor);
      expect(s.fillOpacity, 0.4);
      expect(s.strokeColor, settings.polygonColor);
      expect(s.strokeWidth, 4);
    });
  });
}
