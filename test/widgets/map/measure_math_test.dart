import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/widgets/map/tools/measure_math.dart';

void main() {
  // ~100 m step near the equator (100 / 111320 deg).
  const d = 100 / 111320.0;

  group('haversineMeters', () {
    test('~100 m east along the equator', () {
      expect(haversineMeters(0, 0, 0, d), closeTo(100, 1.0));
    });
    test('zero for identical points', () {
      expect(haversineMeters(1.2, 3.4, 1.2, 3.4), closeTo(0, 1e-6));
    });
  });

  group('polylineLengthMeters', () {
    test('sums two ~100 m segments', () {
      final pts = [const LatLng(0, 0), LatLng(0, d), LatLng(d, d)];
      expect(polylineLengthMeters(pts), closeTo(200, 3));
    });
    test('zero for fewer than 2 points', () {
      expect(polylineLengthMeters([const LatLng(0, 0)]), 0);
      expect(polylineLengthMeters(const []), 0);
    });
  });

  group('polygonAreaSqMeters', () {
    test('~100 m square ≈ 1 ha (10000 m^2)', () {
      final square = [
        const LatLng(0, 0),
        LatLng(0, d),
        LatLng(d, d),
        LatLng(d, 0),
      ];
      expect(polygonAreaSqMeters(square), closeTo(10000, 50));
    });
    test('order-independent (reversed = same area)', () {
      final square = [
        const LatLng(0, 0),
        LatLng(0, d),
        LatLng(d, d),
        LatLng(d, 0),
      ];
      expect(polygonAreaSqMeters(square.reversed.toList()),
          closeTo(polygonAreaSqMeters(square), 1e-3));
    });
    test('zero for fewer than 3 points', () {
      expect(polygonAreaSqMeters([const LatLng(0, 0), LatLng(0, d)]), 0);
    });
  });

  group('initialBearingDeg', () {
    test('north ≈ 0°, east ≈ 90°', () {
      expect(initialBearingDeg(0, 0, d, 0), closeTo(0, 0.5));
      expect(initialBearingDeg(0, 0, 0, d), closeTo(90, 0.5));
    });
    test('always in [0, 360)', () {
      final b = initialBearingDeg(0, 0, -d, -d); // south-west
      expect(b, greaterThanOrEqualTo(0));
      expect(b, lessThan(360));
    });
  });

  group('circleAreaSqMeters', () {
    test('pi r^2', () {
      expect(circleAreaSqMeters(10), closeTo(314.159, 0.01));
    });
  });
}
