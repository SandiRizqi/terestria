import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/widgets/map/tools/coordinate_input.dart';
import 'package:latlong2/latlong.dart';

/// Koordinat yang diketik/ditempel untuk titik alat ukur.

void main() {
  group('parseDecimal', () {
    test('titik atau koma desimal; minus unicode; spasi di tepi', () {
      expect(parseDecimal(' -6.2 '), -6.2);
      expect(parseDecimal('106,8'), 106.8);
      expect(parseDecimal('−6.25'), -6.25);
    });
    test('bukan angka → null', () {
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal('1.2.3'), isNull);
      expect(parseDecimal('NaN'), isNull);
    });
  });

  group('splitCoordinatePair', () {
    test('"lat, lon", "lat lon", "lat;lon", "lat,lon"', () {
      expect(splitCoordinatePair('-6.2, 106.8'), ('-6.2', '106.8'));
      expect(splitCoordinatePair('-6.2 106.8'), ('-6.2', '106.8'));
      expect(splitCoordinatePair('-6,2 106,8'), ('-6,2', '106,8'));
      expect(splitCoordinatePair('-6.2;106.8'), ('-6.2', '106.8'));
      expect(splitCoordinatePair('-6.2,106.8'), ('-6.2', '106.8'));
    });
    test('satu angka berkoma desimal bukan pasangan', () {
      expect(splitCoordinatePair('-6,2'), isNull);
      expect(splitCoordinatePair('-6.2'), isNull);
      expect(splitCoordinatePair('a, b'), isNull);
    });
  });

  group('parseCoordinateInput', () {
    test('valid → titik', () {
      final r = parseCoordinateInput('-6.2', '106,8');
      expect(r.point, const LatLng(-6.2, 106.8));
      expect((r.latError, r.lonError), (null, null));
    });
    test('kosong/bukan angka & di luar rentang → pesan per isian', () {
      final empty = parseCoordinateInput('', 'x');
      expect(empty.point, isNull);
      expect(empty.latError, 'Enter a number');
      expect(empty.lonError, 'Enter a number');

      final range = parseCoordinateInput('91', '-181');
      expect(range.latError, 'Latitude must be between -90 and 90');
      expect(range.lonError, 'Longitude must be between -180 and 180');
      expect(parseCoordinateInput('-90', '180').point, const LatLng(-90, 180));
    });
  });

  test('formatCoordinate: 6 desimal', () {
    expect(formatCoordinate(const LatLng(-6.2, 106.8)), '-6.200000, 106.800000');
  });
}
