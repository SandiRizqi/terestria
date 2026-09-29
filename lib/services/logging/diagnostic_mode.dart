import 'package:shared_preferences/shared_preferences.dart';

/// Mode Diagnostik: saat aktif, log level `debug` (detail per fix, dll.) ikut
/// ditulis ke berkas. Mati otomatis setelah [defaultDuration] agar tak
/// menguras baterai/penyimpanan bila lupa dimatikan. Disimpan di
/// SharedPreferences supaya isolate background juga bisa membacanya.
class DiagnosticMode {
  static const prefsKey = 'diagnostic_until_ms';
  static const defaultDuration = Duration(hours: 24);

  static bool isActive(DateTime? until, DateTime now) =>
      until != null && now.isBefore(until);

  static Future<DateTime?> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Muat ulang: nilai bisa ditulis isolate lain.
    await prefs.reload();
    final ms = prefs.getInt(prefsKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Aktifkan sampai `now + duration`; mengembalikan waktu berakhirnya.
  static Future<DateTime> enable({
    DateTime? now,
    Duration duration = defaultDuration,
  }) async {
    final until = (now ?? DateTime.now()).add(duration);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsKey, until.millisecondsSinceEpoch);
    return until;
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}
