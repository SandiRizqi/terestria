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
  });
}
