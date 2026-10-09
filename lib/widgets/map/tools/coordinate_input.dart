import 'package:latlong2/latlong.dart';

/// Koordinat yang diketik atau ditempel untuk titik alat ukur (derajat
/// desimal). Koma diterima sebagai pemisah desimal ("106,8").

/// Angka desimal dari teks; null bila bukan angka. Menerima koma desimal
/// (bila tak ada titik) dan tanda minus unicode.
double? parseDecimal(String text) {
  var t = text.trim().replaceAll('−', '-');
  if (t.isEmpty) return null;
  if (t.contains(',') && !t.contains('.')) t = t.replaceAll(',', '.');
  final v = double.tryParse(t);
  return v != null && v.isFinite ? v : null;
}

/// Pasangan "lat, lon" / "lat lon" / "lat;lon" / "lat,lon" → dua teks, atau
/// null. Koma tanpa spasi hanya dianggap pemisah bila kedua angka bertitik
/// desimal ("-6,2" tetap satu angka berkoma desimal).
(String, String)? splitCoordinatePair(String text) {
  final t = text.trim();
  final separators = [
    RegExp(r'\s*;\s*'),
    RegExp(r'\s*,\s+'),
    RegExp(r'\s+'),
  ];
  for (final sep in separators) {
    final parts = t.split(sep).where((s) => s.isNotEmpty).toList();
    if (parts.length == 2 &&
        parseDecimal(parts[0]) != null &&
        parseDecimal(parts[1]) != null) {
      return (parts[0], parts[1]);
    }
  }
  final parts = t.split(',');
  if (parts.length == 2 &&
      parts.every((p) => p.contains('.') && parseDecimal(p) != null)) {
    return (parts[0].trim(), parts[1].trim());
  }
  return null;
}

class CoordinateInput {
  final LatLng? point;
  final String? latError;
  final String? lonError;

  const CoordinateInput({this.point, this.latError, this.lonError});
}

/// Baca latitude & longitude; pesan kesalahan per isian bila tidak valid.
CoordinateInput parseCoordinateInput(String lat, String lon) {
  final latV = parseDecimal(lat);
  final lonV = parseDecimal(lon);
  final latError = latV == null
      ? 'Enter a number'
      : (latV < -90 || latV > 90)
          ? 'Latitude must be between -90 and 90'
          : null;
  final lonError = lonV == null
      ? 'Enter a number'
      : (lonV < -180 || lonV > 180)
          ? 'Longitude must be between -180 and 180'
          : null;
  if (latError != null || lonError != null) {
    return CoordinateInput(latError: latError, lonError: lonError);
  }
  return CoordinateInput(point: LatLng(latV!, lonV!));
}

/// "-6.200000, 106.800000" — 6 desimal (±0,1 m).
String formatCoordinate(LatLng p) =>
    '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';
