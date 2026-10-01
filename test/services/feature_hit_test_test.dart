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

    test('sama-sama kena langsung: point → line → polygon; sesama jenis dari '
        'yang terdekat', () {
      final shapes = [
        const HitPolygon('area', ring: _square),
        const HitLine('garis-jauh',
            points: [Offset(0, 54), Offset(100, 54)], halfWidth: 2),
        const HitLine('garis-dekat',
            points: [Offset(0, 52), Offset(100, 52)], halfWidth: 2),
        const HitPoint('titik', center: Offset(52, 50), radius: 8),
      ];
      expect(hitFeatures(const Offset(50, 50), shapes, tolerance: 24),
          ['titik', 'garis-dekat', 'garis-jauh', 'area']);
    });

    test('sama-sama hanya dalam toleransi: urutan sama', () {
      final shapes = [
        const HitPolygon('area', ring: _square), // tepi bawah y=100
        const HitLine('garis', points: [Offset(0, 135), Offset(100, 135)]),
        const HitPoint('titik', center: Offset(50, 140), radius: 8),
      ];
      expect(hitFeatures(const Offset(50, 120), shapes, tolerance: 24),
          ['titik', 'garis', 'area']);
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

  group('dua tingkat: yang kena langsung didahulukan', () {
    List<Offset> square(double x0, double y0, double size) => [
          Offset(x0, y0),
          Offset(x0 + size, y0),
          Offset(x0 + size, y0 + size),
          Offset(x0, y0 + size),
        ];

    test('polygon bersebelahan: tap di dalam A dekat tepi bersama → hanya A',
        () {
      final shapes = [
        HitPolygon('A', ring: square(0, 0, 84)),
        HitPolygon('B', ring: square(84, 0, 84)), // berbagi tepi x = 84
      ];
      expect(hitFeatures(const Offset(64, 42), shapes), ['A']);
      expect(hitFeatures(const Offset(104, 42), shapes), ['B']);
    });

    test('grid 3×3 blok 84 dp: tap di dalam blok tengah tidak pernah '
        'memunculkan daftar pilihan', () {
      final grid = [
        for (var r = 0; r < 3; r++)
          for (var c = 0; c < 3; c++)
            HitPolygon('$r$c', ring: square(c * 84.0, r * 84.0, 84)),
      ];
      for (var x = 84.5; x < 168; x += 4) {
        for (var y = 84.5; y < 168; y += 4) {
          expect(hitFeatures(Offset(x, y), grid), ['11'], reason: '($x, $y)');
        }
      }
    });

    test('celah sempit di luar dua polygon → keduanya (dalam toleransi)', () {
      final shapes = [
        HitPolygon('kiri', ring: square(0, 0, 100)),
        HitPolygon('kanan', ring: square(130, 0, 100)),
      ];
      expect(hitFeatures(const Offset(115, 50), shapes), ['kiri', 'kanan']);
    });

    test('point: tap tepat di P1, P2 30 dp di sebelahnya → hanya P1; di antara '
        'keduanya → keduanya', () {
      final shapes = [
        const HitPoint('P1', center: Offset(0, 0), radius: 12),
        const HitPoint('P2', center: Offset(30, 0), radius: 12),
      ];
      expect(hitFeatures(const Offset(0, 0), shapes), ['P1']);
      expect(hitFeatures(const Offset(15, 0), shapes), ['P1', 'P2']);
    });

    test('line: tap di atas garis A, garis B 20 dp di sebelahnya → hanya A', () {
      final shapes = [
        const HitLine('A', points: [Offset(0, 0), Offset(100, 0)], halfWidth: 1.5),
        const HitLine('B', points: [Offset(0, 20), Offset(100, 20)], halfWidth: 1.5),
      ];
      expect(hitFeatures(const Offset(50, 2), shapes), ['A']);
      expect(hitFeatures(const Offset(50, 10), shapes), ['A', 'B']);
    });

    test('garis tebal: kena langsung sampai setengah tebal + 4 dp', () {
      final shapes = [
        const HitLine('tebal', points: [Offset(0, 0), Offset(100, 0)], halfWidth: 5),
        const HitLine('tipis', points: [Offset(0, 20), Offset(100, 20)]),
      ];
      expect(hitFeatures(const Offset(50, 8), shapes), ['tebal']);
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

      final line = hitShapeFor(geo(3), GeometryType.line, project,
          pointRadius: 12, lineHalfWidth: 2);
      expect((line! as HitLine<GeoData>).points,
          const [Offset(0, 0), Offset(10, 10), Offset(40, 20)]);
      expect((line as HitLine<GeoData>).halfWidth, 2);

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
