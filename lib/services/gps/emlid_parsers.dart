import 'dart:math' as math;

import '../../models/geo_data_model.dart';
import '../../utils/app_logger.dart';

/// Parser murni untuk keluaran posisi Emlid Reach (NMEA / LLH / XYZ).
///
/// Format LLH & XYZ Emlid adalah format solusi RTKLIB yang DIAWALI kolom
/// waktu GPST (`2026/09/29 10:40:54.600` atau `week tow`), contoh LLH:
///
/// ```text
/// 2026/09/29 10:40:54.600  -6.208812345 106.845612345  35.1234  1  18
///   0.0120  0.0100  0.0250  -0.0010  0.0020  -0.0030  1.00  999.9
/// ```
/// kolom: waktu(2) lat lon height Q ns sdn sde sdu sdne sdeu sdun age ratio.
/// Dulu parser membaca kolom tanggal sebagai lintang → tak ada titik sama
/// sekali pada format LLH (format default di UI).
///
/// Semua parser mengisi [GeoPoint.accuracy] (akurasi horizontal, meter) agar
/// UI, dialog simpan, dan ring akurasi tak lagi "N/A"/15 m untuk RTK.
///
/// [GeoPoint.altitude] = tinggi **elipsoid WGS84** untuk SEMUA format (LLH &
/// XYZ memang elipsoid; NMEA dikonversi dari tinggi MSL + geoid separation),
/// sehingga ganti format di Location Provider tak menggeser tinggi puluhan
/// meter.

/// Kualitas RTKLIB (kolom Q) → label kualitas app.
String rtklibQualityLabel(int? q) {
  switch (q) {
    case 1:
      return 'fix';
    case 2:
      return 'float';
    case 3: // SBAS
    case 4: // DGPS
      return 'dgps';
    case 5: // single
    case 6: // PPP
      return 'autonomous';
    default:
      return 'unknown';
  }
}

/// Kualitas NMEA GGA (kolom 6) → label kualitas app. 0 = tak ada fix.
String? nmeaQualityLabel(int q) {
  switch (q) {
    case 0:
      return null;
    case 1:
      return 'autonomous';
    case 2:
      return 'dgps';
    case 4:
      return 'fix';
    case 5:
      return 'float';
    default:
      return 'unknown';
  }
}

/// Perkiraan akurasi horizontal (m) dari HDOP bila GST tak tersedia.
/// Faktor per kualitas adalah perkiraan konservatif galat ukur (UERE).
double estimateAccuracyFromHdop(double hdop, String? quality) {
  final uere = switch (quality) {
    'fix' => 0.02,
    'float' => 0.3,
    'dgps' => 1.0,
    _ => 3.0,
  };
  return hdop * uere;
}

final RegExp _dateToken = RegExp(r'^\d{4}/\d{1,2}/\d{1,2}$');

/// Indeks kolom data pertama sesudah kolom waktu RTKLIB. [dataColumns] =
/// jumlah kolom sesudah waktu (13 untuk LLH & XYZ).
int _rtklibOffset(List<String> t, int dataColumns) {
  if (t.isNotEmpty && _dateToken.hasMatch(t[0])) return 2; // yyyy/mm/dd hh:mm:ss
  if (t.length >= dataColumns + 2) return 2; // week tow
  return 0; // tanpa kolom waktu
}

bool _validLatLon(double lat, double lon) =>
    lat.isFinite &&
    lon.isFinite &&
    lat.abs() <= 90 &&
    lon.abs() <= 180 &&
    !(lat == 0 && lon == 0);

/// Satu baris LLH (RTKLIB/Emlid). Null bila bukan baris posisi yang valid.
GeoPoint? parseRtklibLlh(String line, {DateTime? now}) {
  final t = line.trim().split(RegExp(r'\s+'));
  if (t.length < 5 || line.trimLeft().startsWith('%')) return null;
  final o = _rtklibOffset(t, 13);
  if (t.length < o + 5) return null;
  final lat = double.tryParse(t[o]);
  final lon = double.tryParse(t[o + 1]);
  if (lat == null || lon == null || !_validLatLon(lat, lon)) return null;
  final height = double.tryParse(t[o + 2]);
  final q = int.tryParse(t[o + 3]);
  final ns = int.tryParse(t[o + 4]);
  final sdn = t.length > o + 5 ? double.tryParse(t[o + 5]) : null;
  final sde = t.length > o + 6 ? double.tryParse(t[o + 6]) : null;
  final acc = (sdn != null && sde != null)
      ? math.sqrt(sdn * sdn + sde * sde)
      : null;
  return GeoPoint(
    latitude: lat,
    longitude: lon,
    altitude: height,
    accuracy: acc,
    timestamp: now ?? DateTime.now(),
    fixQuality: rtklibQualityLabel(q),
    satelliteCount: ns,
  );
}

/// Satu baris XYZ/ECEF (RTKLIB/Emlid). Akurasi horizontal diturunkan dari
/// simpangan ECEF (sdx, sdy, sdz) yang diputar ke arah timur/utara.
GeoPoint? parseRtklibXyz(String line, {DateTime? now}) {
  final t = line.trim().split(RegExp(r'\s+'));
  if (t.length < 5 || line.trimLeft().startsWith('%')) return null;
  final o = _rtklibOffset(t, 13);
  if (t.length < o + 5) return null;
  final x = double.tryParse(t[o]);
  final y = double.tryParse(t[o + 1]);
  final z = double.tryParse(t[o + 2]);
  if (x == null || y == null || z == null) return null;
  if (math.sqrt(x * x + y * y + z * z) < 6.0e6) return null; // bukan ECEF bumi
  final llh = ecefToLlh(x, y, z);
  final lat = llh.lat, lon = llh.lon;
  if (!_validLatLon(lat, lon)) return null;
  final q = int.tryParse(t[o + 3]);
  final ns = int.tryParse(t[o + 4]);

  double? acc;
  final sdx = t.length > o + 5 ? double.tryParse(t[o + 5]) : null;
  final sdy = t.length > o + 6 ? double.tryParse(t[o + 6]) : null;
  final sdz = t.length > o + 7 ? double.tryParse(t[o + 7]) : null;
  if (sdx != null && sdy != null && sdz != null) {
    final phi = lat * math.pi / 180, lam = lon * math.pi / 180;
    final sl = math.sin(lam), cl = math.cos(lam);
    final sp = math.sin(phi), cp = math.cos(phi);
    final varE = sl * sl * sdx * sdx + cl * cl * sdy * sdy;
    final varN = sp * sp * cl * cl * sdx * sdx +
        sp * sp * sl * sl * sdy * sdy +
        cp * cp * sdz * sdz;
    acc = math.sqrt(varE + varN);
  }
  return GeoPoint(
    latitude: lat,
    longitude: lon,
    altitude: llh.height,
    accuracy: acc,
    timestamp: now ?? DateTime.now(),
    fixQuality: rtklibQualityLabel(q),
    satelliteCount: ns,
  );
}

/// ECEF (WGS84) → lintang/bujur (derajat) & tinggi elipsoid (m).
({double lat, double lon, double height}) ecefToLlh(
    double x, double y, double z) {
  const a = 6378137.0;
  const e2 = 0.00669437999014;
  final p = math.sqrt(x * x + y * y);
  final lon = math.atan2(y, x);
  var lat = math.atan2(z, p * (1 - e2));
  var height = 0.0;
  for (var i = 0; i < 6; i++) {
    final sinLat = math.sin(lat);
    final n = a / math.sqrt(1 - e2 * sinLat * sinLat);
    height = p / math.cos(lat) - n;
    lat = math.atan2(z, p * (1 - e2 * n / (n + height)));
  }
  return (lat: lat * 180 / math.pi, lon: lon * 180 / math.pi, height: height);
}

/// Pembaca aliran NMEA ber-state: menggabungkan `GGA` (posisi) dengan `GST`
/// (simpangan lat/lon) untuk akurasi yang sebenarnya; tanpa GST, akurasi
/// diperkirakan dari HDOP. Menerima talker apa pun (GP/GN/GL/GA/GB…) dan
/// memverifikasi checksum bila ada.
class NmeaStreamParser {
  double? _gstAccuracy;
  String? _gstTime;
  bool _warnedNoGeoidSeparation = false;

  /// Proses satu kalimat; mengembalikan titik untuk `GGA` yang valid.
  GeoPoint? parse(String rawLine, {DateTime? now}) {
    final line = rawLine.trim();
    if (!line.startsWith(r'$') || line.length < 7) return null;
    if (!nmeaChecksumOk(line)) return null;
    final body = line.contains('*') ? line.substring(0, line.indexOf('*')) : line;
    final parts = body.split(',');
    final type = parts[0].length >= 6 ? parts[0].substring(3, 6) : '';

    if (type == 'GST' && parts.length >= 8) {
      final latErr = double.tryParse(parts[6]);
      final lonErr = double.tryParse(parts[7]);
      if (latErr != null && lonErr != null) {
        _gstAccuracy = math.sqrt(latErr * latErr + lonErr * lonErr);
        _gstTime = parts[1];
      }
      return null;
    }
    if (type != 'GGA' || parts.length < 10) return null;

    final latStr = parts[2], latDir = parts[3];
    final lonStr = parts[4], lonDir = parts[5];
    if (latStr.length < 4 || lonStr.length < 5) return null;
    final q = int.tryParse(parts[6]) ?? 0;
    final quality = nmeaQualityLabel(q);
    if (quality == null) return null; // tak ada fix

    final latDeg = double.tryParse(latStr.substring(0, 2));
    final latMin = double.tryParse(latStr.substring(2));
    final lonDeg = double.tryParse(lonStr.substring(0, 3));
    final lonMin = double.tryParse(lonStr.substring(3));
    if (latDeg == null || latMin == null || lonDeg == null || lonMin == null) {
      return null;
    }
    var lat = latDeg + latMin / 60;
    var lon = lonDeg + lonMin / 60;
    if (latDir == 'S') lat = -lat;
    if (lonDir == 'W') lon = -lon;
    if (!_validLatLon(lat, lon)) return null;

    final hdop = double.tryParse(parts[8]);
    double? acc;
    // GST biasanya datang SESUDAH GGA epoch yang sama → pakai GST terbaru
    // bila selisih waktunya ≤ 2 dtk (epoch ini atau sebelumnya).
    final ggaSec = _secondsOfDay(parts[1]);
    final gstSec = _gstTime == null ? null : _secondsOfDay(_gstTime!);
    if (_gstAccuracy != null &&
        ggaSec != null &&
        gstSec != null &&
        (ggaSec - gstSec).abs() <= 2.0) {
      acc = _gstAccuracy;
    } else if (hdop != null && hdop > 0) {
      acc = estimateAccuracyFromHdop(hdop, quality);
    }

    // GGA kolom 9 = tinggi di atas MSL (geoid), kolom 11 = geoid separation
    // N → tinggi elipsoid h = H + N (seragam dengan LLH/XYZ). Tanpa N tak bisa
    // dikonversi: tetap MSL (dicatat sekali).
    final msl = double.tryParse(parts[9]);
    final geoidSeparation = parts.length > 11 ? double.tryParse(parts[11]) : null;
    double? altitude = msl;
    if (msl != null) {
      if (geoidSeparation != null) {
        altitude = msl + geoidSeparation;
      } else if (!_warnedNoGeoidSeparation) {
        _warnedNoGeoidSeparation = true;
        logWarn('NMEA GGA has no geoid separation — altitude stays above '
            'mean sea level (not ellipsoidal)', tag: 'EMLID');
      }
    }

    return GeoPoint(
      latitude: lat,
      longitude: lon,
      altitude: altitude,
      accuracy: acc,
      timestamp: now ?? DateTime.now(),
      fixQuality: quality,
      satelliteCount: int.tryParse(parts[7]),
    );
  }
}

/// `hhmmss.ss` → detik sejak tengah malam (UTC); null bila tak valid.
double? _secondsOfDay(String t) {
  if (t.length < 6) return null;
  final h = int.tryParse(t.substring(0, 2));
  final m = int.tryParse(t.substring(2, 4));
  final sec = double.tryParse(t.substring(4));
  if (h == null || m == null || sec == null) return null;
  return h * 3600 + m * 60 + sec;
}

/// Checksum NMEA (`*hh`) valid, atau tak ada checksum (diterima).
bool nmeaChecksumOk(String line) {
  final star = line.indexOf('*');
  if (star < 0) return true;
  if (line.length < star + 3) return false;
  final expected = int.tryParse(line.substring(star + 1, star + 3), radix: 16);
  if (expected == null) return false;
  var sum = 0;
  for (var i = 1; i < star; i++) {
    sum ^= line.codeUnitAt(i);
  }
  return sum == expected;
}
