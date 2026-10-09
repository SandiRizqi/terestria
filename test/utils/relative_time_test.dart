import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/utils/relative_time.dart';

/// Waktu relatif singkat untuk header project dan daftar project
/// ("updated 2 h ago", "248 records · yesterday").

final _now = DateTime(2026, 10, 9, 14, 30);

void main() {
  test('kurang dari semenit (atau jam HP mundur) → "just now"', () {
    expect(relativeTime(DateTime(2026, 10, 9, 14, 29, 40), _now), 'just now');
    expect(relativeTime(DateTime(2026, 10, 9, 14, 35), _now), 'just now');
  });

  test('menit dan jam', () {
    expect(relativeTime(DateTime(2026, 10, 9, 14, 25), _now), '5 min ago');
    expect(relativeTime(DateTime(2026, 10, 9, 12, 20), _now), '2 h ago');
  });

  test('hari kemarin → "yesterday"; beberapa hari → "N d ago"', () {
    expect(relativeTime(DateTime(2026, 10, 8, 9), _now), 'yesterday');
    expect(relativeTime(DateTime(2026, 10, 4, 9), _now), '5 d ago');
  });

  test('lebih dari seminggu → tanggal', () {
    expect(relativeTime(DateTime(2026, 9, 1), _now), '1 Sep');
    expect(relativeTime(DateTime(2025, 12, 31), _now), '31 Dec 2025');
  });
}
