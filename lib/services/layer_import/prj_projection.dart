import 'dart:math' as math;

import 'layer_importer.dart';
import 'shapefile_reader.dart';

/// Transform koordinat shapefile → WGS84 `[lon, lat]` dari isi `.prj` (WKT
/// OGC/ESRI).
///
/// Didukung: geografis WGS84 (apa adanya) dan Transverse Mercator di datum
/// WGS84 (UTM zona N/S; juga TM lain berparameter lengkap). Datum DGN95
/// (Indonesia) diperlakukan setara WGS84 (selisih < 1 m). Tanpa `.prj`:
/// diterima hanya bila [bbox] tampak derajat. Selain itu →
/// [LayerImportException] dengan pesan jelas (bukan salah posisi diam-diam).
///
/// [bbox] = `[xmin, ymin, xmax, ymax]` dari header `.shp`.
CoordTransform? transformFromPrj(String? prj, {required List<double> bbox}) {
  final wkt = (prj ?? '').trim();
  if (wkt.isEmpty) {
    if (_looksLikeDegrees(bbox)) return null;
    throw const LayerImportException(
        'The shapefile has no .prj and its coordinates are not degrees — '
        'include the .prj file (WGS84 / UTM WGS84) in the zip');
  }

  final upper = wkt.toUpperCase();
  final name = _crsName(wkt);
  if (!_isWgs84Datum(upper)) {
    throw LayerImportException(
        'Projection "$name" is not supported yet. Use WGS84 (EPSG:4326) or '
        'UTM WGS84 and export the shapefile again');
  }

  if (upper.startsWith('GEOGCS') || upper.startsWith('GEOGCRS')) {
    return null; // sudah lon/lat
  }
  if (!(upper.startsWith('PROJCS') || upper.startsWith('PROJCRS')) ||
      !upper.contains('TRANSVERSE_MERCATOR') &&
          !upper.contains('TRANSVERSE MERCATOR')) {
    throw LayerImportException(
        'Projection "$name" is not supported yet. Use WGS84 (EPSG:4326) or '
        'UTM WGS84 and export the shapefile again');
  }

  final p = _parameters(wkt);
  final unit = _linearUnit(wkt);
  final tm = TransverseMercator(
    centralMeridian: p['central_meridian'] ?? p['longitude_of_natural_origin'] ?? 0,
    latitudeOfOrigin:
        p['latitude_of_origin'] ?? p['latitude_of_natural_origin'] ?? 0,
    scaleFactor: p['scale_factor'] ?? p['scale_factor_at_natural_origin'] ?? 1,
    falseEasting: (p['false_easting'] ?? 0) * unit,
    falseNorthing: (p['false_northing'] ?? 0) * unit,
  );
  return (x, y) => tm.inverse(x * unit, y * unit);
}

/// Contoh UTM: zona 1–60, belahan selatan pakai false northing 10.000.000.
TransverseMercator utmZone(int zone, {required bool south}) =>
    TransverseMercator(
      centralMeridian: -183.0 + 6 * zone,
      latitudeOfOrigin: 0,
      scaleFactor: 0.9996,
      falseEasting: 500000,
      falseNorthing: south ? 10000000 : 0,
    );

bool _looksLikeDegrees(List<double> b) =>
    b.length == 4 &&
    b.every((v) => v.isFinite) &&
    b[0] >= -180 &&
    b[2] <= 180 &&
    b[1] >= -90 &&
    b[3] <= 90;

bool _isWgs84Datum(String upper) {
  final datum = RegExp(r'DATUM\s*\[\s*"([^"]*)"').firstMatch(upper)?.group(1) ??
      '';
  final d = datum.replaceAll(RegExp(r'[\s_\-]'), '');
  return d.contains('WGS1984') ||
      d.contains('WGS84') ||
      d.contains('WORLDGEODETICSYSTEM1984') ||
      d.contains('DGN95') ||
      d.contains('DGN1995') ||
      d.contains('GEODESINASIONAL1995') ||
      d.contains('INDONESIAGEODETICDATUM1995');
}

String _crsName(String wkt) =>
    RegExp(r'^\s*\w+\s*\[\s*"([^"]*)"').firstMatch(wkt)?.group(1) ?? wkt;

/// `PARAMETER["name", value]` → map dengan kunci huruf kecil.
Map<String, double> _parameters(String wkt) {
  final out = <String, double>{};
  for (final m in RegExp(r'PARAMETER\s*\[\s*"([^"]+)"\s*,\s*([-+0-9.eE]+)',
          caseSensitive: false)
      .allMatches(wkt)) {
    final v = double.tryParse(m.group(2)!);
    if (v != null) {
      out[m.group(1)!.toLowerCase().replaceAll(' ', '_')] = v;
    }
  }
  return out;
}

/// Faktor unit linear PROJCS terakhir (`UNIT["Meter",1.0]`); default meter.
double _linearUnit(String wkt) {
  final units = RegExp(r'UNIT\s*\[\s*"([^"]*)"\s*,\s*([-+0-9.eE]+)',
          caseSensitive: false)
      .allMatches(wkt)
      .toList();
  // Unit pertama di GEOGCS = derajat; unit linear = yang terakhir.
  for (final m in units.reversed) {
    final name = m.group(1)!.toLowerCase();
    if (name.contains('degree')) continue;
    return double.tryParse(m.group(2)!) ?? 1;
  }
  return 1;
}

/// Transverse Mercator ellipsoid WGS84 (deret Krüger orde 6, galat < 1 mm
/// dalam ±~40° dari meridian tengah).
class TransverseMercator {
  final double centralMeridian;
  final double latitudeOfOrigin;
  final double scaleFactor;
  final double falseEasting;
  final double falseNorthing;

  TransverseMercator({
    required this.centralMeridian,
    required this.latitudeOfOrigin,
    required this.scaleFactor,
    required this.falseEasting,
    required this.falseNorthing,
  }) : _m0 = _meridianScaled(latitudeOfOrigin);

  static const double _a = 6378137.0;
  static const double _f = 1 / 298.257223563;
  static const double _n = _f / (2 - _f);
  static final double _e = math.sqrt(_f * (2 - _f));
  static final double _bigA = _a /
      (1 + _n) *
      (1 + _n * _n / 4 + math.pow(_n, 4) / 64 + math.pow(_n, 6) / 256);

  static final List<double> _alpha = () {
    final n = _n, n2 = n * n, n3 = n2 * n, n4 = n3 * n, n5 = n4 * n, n6 = n5 * n;
    return <double>[
      0.0,
      n / 2 - 2 * n2 / 3 + 5 * n3 / 16 + 41 * n4 / 180 - 127 * n5 / 288 +
          7891 * n6 / 37800,
      13 * n2 / 48 - 3 * n3 / 5 + 557 * n4 / 1440 + 281 * n5 / 630 -
          1983433 * n6 / 1935360,
      61 * n3 / 240 - 103 * n4 / 140 + 15061 * n5 / 26880 +
          167603 * n6 / 181440,
      49561 * n4 / 161280 - 179 * n5 / 168 + 6601661 * n6 / 7257600,
      34729 * n5 / 80640 - 3418889 * n6 / 1995840,
      212378941 * n6 / 319334400,
    ];
  }();

  static final List<double> _beta = () {
    final n = _n, n2 = n * n, n3 = n2 * n, n4 = n3 * n, n5 = n4 * n, n6 = n5 * n;
    return <double>[
      0.0,
      n / 2 - 2 * n2 / 3 + 37 * n3 / 96 - n4 / 360 - 81 * n5 / 512 +
          96199 * n6 / 604800,
      n2 / 48 + n3 / 15 - 437 * n4 / 1440 + 46 * n5 / 105 -
          1118711 * n6 / 3870720,
      17 * n3 / 480 - 37 * n4 / 840 - 209 * n5 / 4480 + 5569 * n6 / 90720,
      4397 * n4 / 161280 - 11 * n5 / 504 - 830251 * n6 / 7257600,
      4583 * n5 / 161280 - 108847 * n6 / 3991680,
      20648693 * n6 / 638668800,
    ];
  }();

  final double _m0;

  /// Jarak meridian (tanpa skala) dari ekuator ke lintang [latDeg].
  static double _meridianScaled(double latDeg) {
    if (latDeg == 0) return 0;
    final xi = _conformalXi(latDeg * math.pi / 180, 0);
    var s = xi;
    for (var j = 1; j <= 6; j++) {
      s += _alpha[j] * math.sin(2 * j * xi);
    }
    return _bigA * s;
  }

  static double _conformalXi(double phi, double lam) {
    final t = _sinhAtanh(phi);
    return math.atan2(t, math.cos(lam));
  }

  static double _sinhAtanh(double phi) {
    final s = math.sin(phi);
    final v = _atanh(s) - _e * _atanh(_e * s);
    return (math.exp(v) - math.exp(-v)) / 2;
  }

  static double _atanh(double x) => 0.5 * math.log((1 + x) / (1 - x));

  /// Lon/lat (derajat) → easting/northing (meter).
  List<double> forward(double lonDeg, double latDeg) {
    final phi = latDeg * math.pi / 180;
    final lam = (lonDeg - centralMeridian) * math.pi / 180;
    final t = _sinhAtanh(phi);
    final xiP = math.atan2(t, math.cos(lam));
    final etaP = _atanh(math.sin(lam) / math.sqrt(1 + t * t));
    var xi = xiP, eta = etaP;
    for (var j = 1; j <= 6; j++) {
      xi += _alpha[j] * math.sin(2 * j * xiP) * _cosh(2 * j * etaP);
      eta += _alpha[j] * math.cos(2 * j * xiP) * _sinh(2 * j * etaP);
    }
    return <double>[
      falseEasting + scaleFactor * _bigA * eta,
      falseNorthing + scaleFactor * (_bigA * xi - _m0),
    ];
  }

  /// Easting/northing (meter) → `[lon, lat]` (derajat).
  List<double> inverse(double easting, double northing) {
    final xi = (northing - falseNorthing + scaleFactor * _m0) /
        (scaleFactor * _bigA);
    final eta = (easting - falseEasting) / (scaleFactor * _bigA);
    var xiP = xi, etaP = eta;
    for (var j = 1; j <= 6; j++) {
      xiP -= _beta[j] * math.sin(2 * j * xi) * _cosh(2 * j * eta);
      etaP -= _beta[j] * math.cos(2 * j * xi) * _sinh(2 * j * eta);
    }
    final sinhEtaP = _sinh(etaP);
    final tau0 = math.sin(xiP) / math.sqrt(sinhEtaP * sinhEtaP + math.pow(math.cos(xiP), 2));
    final lam = math.atan2(sinhEtaP, math.cos(xiP));
    // τ' → τ (lintang geodetik) via iterasi Newton (Karney 2011).
    var tau = tau0;
    for (var i = 0; i < 6; i++) {
      final sig = _sinh(_e * _atanh(_e * tau / math.sqrt(1 + tau * tau)));
      final tauP = tau * math.sqrt(1 + sig * sig) - sig * math.sqrt(1 + tau * tau);
      final dTau = (tau0 - tauP) /
          math.sqrt(1 + tauP * tauP) *
          (1 + (1 - _e * _e) * tau * tau) /
          ((1 - _e * _e) * math.sqrt(1 + tau * tau));
      tau += dTau;
      if (dTau.abs() < 1e-12) break;
    }
    final lat = math.atan(tau) * 180 / math.pi;
    final lon = centralMeridian + lam * 180 / math.pi;
    return [lon, lat];
  }

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
}
