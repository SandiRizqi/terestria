import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/gps/emlid_parsers.dart';

/// Tambahkan checksum NMEA yang benar ke badan kalimat (tanpa `$`/`*`).
String nmea(String body) {
  var sum = 0;
  for (final c in body.codeUnits) {
    sum ^= c;
  }
  return '\$$body*${sum.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}

/// WGS84 lat/lon/h → ECEF, untuk membuat baris XYZ uji.
({double x, double y, double z}) toEcef(double latDeg, double lonDeg, double h) {
  const a = 6378137.0, e2 = 0.00669437999014;
  final lat = latDeg * math.pi / 180, lon = lonDeg * math.pi / 180;
  final n = a / math.sqrt(1 - e2 * math.sin(lat) * math.sin(lat));
  return (
    x: (n + h) * math.cos(lat) * math.cos(lon),
    y: (n + h) * math.cos(lat) * math.sin(lon),
    z: (n * (1 - e2) + h) * math.sin(lat),
  );
}

void main() {
  group('LLH (RTKLIB/Emlid)', () {
    test('baris dengan tanggal & jam: kolom posisi dibaca dengan benar', () {
      final p = parseRtklibLlh(
          '2026/09/29 10:40:54.600   -6.208812345  106.845612345    35.1234'
          '   1  18   0.0120   0.0090   0.0250  -0.0010   0.0020  -0.0030'
          '   1.00  999.9')!;
      expect(p.latitude, closeTo(-6.208812345, 1e-9));
      expect(p.longitude, closeTo(106.845612345, 1e-9));
      expect(p.altitude, closeTo(35.1234, 1e-6));
      expect(p.fixQuality, 'fix');
      expect(p.satelliteCount, 18);
      expect(p.accuracy, closeTo(0.015, 1e-6)); // sqrt(0.012² + 0.009²)
    });

    test('format waktu week/tow juga didukung', () {
      final p = parseRtklibLlh(
          '2386 123456.000  2.2395458 116.9953588 20.5 2 12 0.3 0.4 0.9 0 0 0 1.0 3.1')!;
      expect(p.latitude, closeTo(2.2395458, 1e-9));
      expect(p.fixQuality, 'float');
      expect(p.accuracy, closeTo(0.5, 1e-9));
    });

    test('header & sampah diabaikan', () {
      expect(parseRtklibLlh('% (lat/lon/height=WGS84/ellipsoidal)'), isNull);
      expect(parseRtklibLlh('hello world'), isNull);
      expect(parseRtklibLlh(''), isNull);
    });

    test('kode kualitas RTKLIB', () {
      expect(rtklibQualityLabel(1), 'fix');
      expect(rtklibQualityLabel(2), 'float');
      expect(rtklibQualityLabel(4), 'dgps');
      expect(rtklibQualityLabel(5), 'autonomous');
      expect(rtklibQualityLabel(null), 'unknown');
    });
  });

  group('XYZ (ECEF)', () {
    test('ECEF → lat/lon kembali ke posisi asal', () {
      final e = toEcef(-6.2088, 106.8456, 35.0);
      final p = parseRtklibXyz('2026/09/29 10:40:54.600 '
          '${e.x.toStringAsFixed(4)} ${e.y.toStringAsFixed(4)} '
          '${e.z.toStringAsFixed(4)} 1 20 0.010 0.010 0.010 0 0 0 1.0 50.0')!;
      expect(p.latitude, closeTo(-6.2088, 1e-7));
      expect(p.longitude, closeTo(106.8456, 1e-7));
      expect(p.altitude, closeTo(35.0, 1e-3));
      expect(p.fixQuality, 'fix');
      // σ ECEF isotropik 1 cm → horizontal ≈ √2 cm.
      expect(p.accuracy, closeTo(0.01414, 1e-4));
    });

    test('nilai bukan ECEF bumi ditolak', () {
      expect(parseRtklibXyz('1 2 3 1 5'), isNull);
    });
  });

  group('NMEA', () {
    test('GGA RTK fix + GST → akurasi dari GST', () {
      final parser = NmeaStreamParser();
      final gga = nmea('GNGGA,104054.60,0612.52874,S,10650.73674,E,4,18,0.7,'
          '35.1,M,17.0,M,1.0,0000');
      final gst = nmea('GNGST,104054.60,0.5,0.02,0.01,45.0,0.012,0.009,0.025');
      final first = parser.parse(gga)!; // GST belum datang → dari HDOP
      expect(first.fixQuality, 'fix');
      expect(first.latitude, closeTo(-(6 + 12.52874 / 60), 1e-9));
      expect(first.longitude, closeTo(106 + 50.73674 / 60, 1e-9));
      expect(first.satelliteCount, 18);
      expect(first.accuracy, closeTo(0.7 * 0.02, 1e-9));

      expect(parser.parse(gst), isNull); // GST tak menghasilkan titik
      final second = parser.parse(nmea('GNGGA,104054.80,0612.52874,S,'
          '10650.73674,E,4,18,0.7,35.1,M,17.0,M,1.0,0000'))!;
      expect(second.accuracy, closeTo(0.015, 1e-9));
    });

    test('talker lain (GA/GP) diterima; kualitas 0 & checksum salah ditolak', () {
      final parser = NmeaStreamParser();
      expect(
          parser.parse(nmea('GAGGA,000000.00,0100.00000,N,10000.00000,E,5,'
              '10,1.0,5.0,M,0.0,M,,'))!
              .fixQuality,
          'float');
      expect(
          parser.parse(nmea('GPGGA,000000.00,0100.00000,N,10000.00000,E,0,'
              '0,,,M,,M,,')),
          isNull);
      expect(
          parser.parse(r'$GPGGA,000000.00,0100.00000,N,10000.00000,E,1,'
              r'8,1.0,5.0,M,0.0,M,,*00'),
          isNull);
    });

    test('tinggi = elipsoid WGS84 (MSL + geoid separation), seragam dengan '
        'LLH/XYZ', () {
      final p = NmeaStreamParser().parse(nmea('GNGGA,104054.60,0612.52874,S,'
          '10650.73674,E,4,18,0.7,35.1,M,17.0,M,1.0,0000'))!;
      expect(p.altitude, closeTo(52.1, 1e-9));
    });

    test('tanpa geoid separation → tetap tinggi MSL (tak bisa dikonversi)', () {
      final p = NmeaStreamParser().parse(nmea('GPGGA,000000.00,0100.00000,N,'
          '10000.00000,E,1,8,1.2,5.0,M,,M,,'))!;
      expect(p.altitude, closeTo(5.0, 1e-9));
    });

    test('tanpa checksum tetap diterima', () {
      final p = NmeaStreamParser().parse(r'$GPGGA,000000.00,0100.00000,N,'
          r'10000.00000,E,1,8,1.2,5.0,M,0.0,M,,');
      expect(p!.fixQuality, 'autonomous');
      expect(p.accuracy, closeTo(3.6, 1e-9));
    });
  });
}
