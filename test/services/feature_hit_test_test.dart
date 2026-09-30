import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/map/feature_hit_test.dart';

/// Hit-test tap langsung pada feature (T9) — murni, di ruang piksel layar.
/// Urutan hasil: point (terdekat) → line (terdekat) → polygon (terkecil).

const _square = [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)];
const _smallSquare = [
  Offset(40, 40),
  Offset(60, 40),
  Offset(60, 60),
  Offset(40, 60),
];

void main() {
  group('point', () {
    test('kena bila jarak ≤ radius marker + toleransi', () {
      final shapes = [const HitPoint('p', center: Offset(50, 50), radius: 10)];
      expect(hitFeatures(const Offset(50, 83), shapes, tolerance: 24), ['p']);
      expect(hitFeatures(const Offset(50, 85), shapes, tolerance: 24), isEmpty);
    });
  });

  group('line', () {
    const line = HitLine('l', points: [Offset(0, 0), Offset(100, 0)]);

    test('kena bila jarak ke segmen ≤ toleransi', () {
      expect(hitFeatures(const Offset(50, 20), [line], tolerance: 24), ['l']);
      expect(hitFeatures(const Offset(50, 30), [line], tolerance: 24), isEmpty);
    });

    test('di luar ujung segmen: jarak diukur ke titik ujung', () {
      expect(hitFeatures(const Offset(120, 0), [line], tolerance: 24), ['l']);
      expect(hitFeatures(const Offset(130, 10), [line], tolerance: 24), isEmpty);
    });
  });

  group('polygon', () {
    const poly = HitPolygon('a', ring: _square);

    test('kena bila tap di dalam area', () {
      expect(hitFeatures(const Offset(50, 50), [poly], tolerance: 0), ['a']);
    });

    test('di luar tapi dekat garis tepi (≤ toleransi) tetap kena', () {
      expect(hitFeatures(const Offset(110, 50), [poly], tolerance: 24), ['a']);
      expect(hitFeatures(const Offset(130, 50), [poly], tolerance: 24), isEmpty);
    });

    test('ring tertutup (titik awal = akhir) sama saja', () {
      const closed = HitPolygon('c', ring: [..._square, Offset(0, 0)]);
      expect(hitFeatures(const Offset(50, 50), [closed], tolerance: 0), ['c']);
    });
  });

  group('beberapa hit', () {
    test('polygon bertumpuk: yang terkecil dulu', () {
      final shapes = [
        const HitPolygon('besar', ring: _square),
        const HitPolygon('kecil', ring: _smallSquare),
      ];
      expect(hitFeatures(const Offset(50, 50), shapes, tolerance: 0),
          ['kecil', 'besar']);
    });

    test('point → line → polygon; sesama jenis dari yang terdekat', () {
      final shapes = [
        const HitPolygon('area', ring: _square),
        const HitLine('garis-jauh', points: [Offset(0, 70), Offset(100, 70)]),
        const HitLine('garis-dekat', points: [Offset(0, 55), Offset(100, 55)]),
        const HitPoint('titik', center: Offset(52, 50), radius: 8),
      ];
      expect(hitFeatures(const Offset(50, 50), shapes, tolerance: 24),
          ['titik', 'garis-dekat', 'garis-jauh', 'area']);
    });

    test('jarak sama → urutan masukan dipertahankan (stabil)', () {
      final shapes = [
        const HitPoint('satu', center: Offset(40, 50), radius: 8),
        const HitPoint('dua', center: Offset(60, 50), radius: 8),
      ];
      expect(hitFeatures(const Offset(50, 50), shapes, tolerance: 24),
          ['satu', 'dua']);
    });
  });

  test('geometri rusak diabaikan; tanpa bentuk → kosong', () {
    final shapes = [
      const HitLine('line-1-titik', points: [Offset(50, 50)]),
      const HitPolygon('poly-2-titik', ring: [Offset(0, 0), Offset(100, 100)]),
    ];
    expect(hitFeatures(const Offset(50, 50), shapes, tolerance: 24), isEmpty);
    expect(hitFeatures(const Offset(50, 50), const <HitShape<String>>[]), isEmpty);
  });

  group('hitShapeFor (GeoData → bentuk layar)', () {
    GeoData geo(int points) => GeoData(
          id: 'g$points',
          projectId: 'p',
          formData: const {},
          points: [
            for (var i = 0; i < points; i++)
              GeoPoint(
                  latitude: i.toDouble(),
                  longitude: (i * i).toDouble(),
                  timestamp: DateTime.utc(2026)),
          ],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
    // Proyeksi linear sederhana: x = lon × 10, y = lat × 10.
    Offset project(GeoPoint p) => Offset(p.longitude * 10, p.latitude * 10);

    test('sesuai geometri project', () {
      final point = hitShapeFor(geo(1), GeometryType.point, project, pointRadius: 12);
      expect(point, isA<HitPoint<GeoData>>());
      expect((point! as HitPoint<GeoData>).radius, 12);

      final line = hitShapeFor(geo(3), GeometryType.line, project, pointRadius: 12);
      expect((line! as HitLine<GeoData>).points,
          const [Offset(0, 0), Offset(10, 10), Offset(40, 20)]);

      expect(hitShapeFor(geo(3), GeometryType.polygon, project, pointRadius: 12),
          isA<HitPolygon<GeoData>>());
    });

    test('titik kurang → null', () {
      expect(hitShapeFor(geo(0), GeometryType.point, project, pointRadius: 12), isNull);
      expect(hitShapeFor(geo(1), GeometryType.line, project, pointRadius: 12), isNull);
      expect(hitShapeFor(geo(2), GeometryType.polygon, project, pointRadius: 12), isNull);
    });
  });
}
