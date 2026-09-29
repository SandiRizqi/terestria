/// Konversi nilai JSON yang toleran untuk data dari server/DB lama.
///
/// Server bisa mengirim angka sebagai int (`0`), double (`0.0`), atau string
/// (`"0.0"`, mis. Decimal Django); boolean sebagai `true`/`1`/`"true"`.
/// Meng-assign `dynamic` langsung ke `double` melempar TypeError untuk int —
/// satu record seperti itu dulu membuat seluruh halaman pull gagal.
library;

double? parseDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

/// Sama seperti [parseDouble] tapi wajib ada; melempar [FormatException]
/// dengan nama field agar log menunjukkan apa yang rusak.
double requireDouble(Object? v, String field) {
  final d = parseDouble(v);
  if (d == null || d.isNaN || d.isInfinite) {
    throw FormatException('Invalid or missing number for "$field": $v');
  }
  return d;
}

int? parseInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final s = v.trim();
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }
  return null;
}

bool parseBool(Object? v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return fallback;
}

/// ISO-8601 string atau epoch milidetik → DateTime LOKAL (seragam dengan
/// nilai yang dibaca dari SQLite). Null bila kosong/tak valid.
DateTime? parseDateTime(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String && v.trim().isNotEmpty) {
    return DateTime.tryParse(v.trim())?.toLocal();
  }
  return null;
}

DateTime requireDateTime(Object? v, String field) {
  final d = parseDateTime(v);
  if (d == null) {
    throw FormatException('Invalid or missing date for "$field": $v');
  }
  return d;
}

String? parseString(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}
