import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/theme/road_vector_style.dart';

/// Pemetaan `highway` OSM → gaya garis basemap jalan.
/// Kelas kendaraan digambar (tebal berjenjang), kelas pejalan-kaki dilewati,
/// kelas dikenal-tapi-tak-terpetakan pakai default.
void main() {
  group('RoadVectorStyle.forHighway', () {
    test('kelas kendaraan → ada gaya', () {
      expect(RoadVectorStyle.forHighway('motorway'), isNotNull);
      expect(RoadVectorStyle.forHighway('residential'), isNotNull);
    });

    test('jalan besar lebih tebal dari jalan kecil (berjenjang)', () {
      final motorway = RoadVectorStyle.forHighway('motorway')!;
      final residential = RoadVectorStyle.forHighway('residential')!;
      final primary = RoadVectorStyle.forHighway('primary')!;
      final tertiary = RoadVectorStyle.forHighway('tertiary')!;
      expect(motorway.strokeWidth, greaterThan(residential.strokeWidth));
      expect(primary.strokeWidth, greaterThan(tertiary.strokeWidth));
    });

    test('kelas non-jalan (pejalan kaki) → null (dilewati)', () {
      for (final h in ['footway', 'path', 'steps', 'cycleway', 'pedestrian']) {
        expect(RoadVectorStyle.forHighway(h), isNull, reason: h);
      }
    });

    test('track (jalan kebun) tetap digambar', () {
      expect(RoadVectorStyle.forHighway('track'), isNotNull);
    });

    test('kelas dikenal-tapi-tak-terpetakan → default', () {
      final s = RoadVectorStyle.forHighway('busway');
      expect(s, isNotNull);
      expect(s!.strokeWidth, RoadVectorStyle.defaultStyle.strokeWidth);
      expect(s.color, RoadVectorStyle.defaultStyle.color);
    });

    test('null / kosong → null', () {
      expect(RoadVectorStyle.forHighway(null), isNull);
      expect(RoadVectorStyle.forHighway(''), isNull);
    });

    test('warna berbeda antara kelas utama dan kelas pemukiman', () {
      expect(RoadVectorStyle.forHighway('motorway')!.color,
          isNot(RoadVectorStyle.forHighway('residential')!.color));
    });

    test('palet TAP: warna per kelas sesuai style MapLibre', () {
      expect(RoadVectorStyle.forHighway('primary')!.color,
          const Color(0xFFE65100));
      expect(RoadVectorStyle.forHighway('secondary')!.color,
          const Color(0xFFF57C00));
      expect(RoadVectorStyle.forHighway('tertiary')!.color,
          const Color(0xFFFBC02D));
      expect(RoadVectorStyle.forHighway('residential')!.color,
          const Color(0xFFBDBDBD));
      expect(RoadVectorStyle.forHighway('service')!.color,
          const Color(0xFF9E9E9E));
      expect(RoadVectorStyle.forHighway('track')!.color,
          const Color(0xFFA1887F));
      // major (primary/trunk/motorway) memakai oranye yang sama.
      expect(RoadVectorStyle.forHighway('motorway')!.color,
          const Color(0xFFE65100));
      // default (kelas tak terpetakan) abu-abu netral.
      expect(RoadVectorStyle.defaultStyle.color, const Color(0xFF999999));
    });
  });
}
