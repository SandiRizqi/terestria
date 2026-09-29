/// Menyamarkan rahasia (token, kredensial) sebelum baris log ditulis ke berkas
/// yang bisa dibagikan user. Koordinat & teks biasa tidak diubah.
class LogRedactor {
  static const _mask = '***';

  static final List<(RegExp, String Function(Match))> _rules = [
    // JWT telanjang: header.payload.signature
    (
      RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'),
      (_) => _mask
    ),
    // Token FCM: <id>:APA91b...
    (RegExp(r'[A-Za-z0-9_\-]{10,}:APA91b[A-Za-z0-9_\-]+'), (_) => _mask),
    // Header Authorization (dengan/ tanpa skema)
    (
      RegExp(
          r'''(authorization["']?\s*[:=]\s*["']?)(?:(?:bearer|basic|token)\s+)?[^\s,"'}]+''',
          caseSensitive: false),
      (m) => '${m[1]}$_mask'
    ),
    // "Bearer xxx" di mana pun
    (
      RegExp(r'\b(bearer)\s+[A-Za-z0-9\-._~+/=]+', caseSensitive: false),
      (m) => '${m[1]} $_mask'
    ),
    // Pasangan kunci-nilai sensitif: password=..., "token":"...", api_key: ...
    (
      RegExp(
          r'''(["']?(?:password|passwd|pwd|access_token|refresh_token|token|secret|api[_\-]?key)["']?\s*[:=]\s*["']?)[^\s,"'}&]+''',
          caseSensitive: false),
      (m) => '${m[1]}$_mask'
    ),
  ];

  static String redact(String input) {
    var out = input;
    for (final (re, replace) in _rules) {
      out = out.replaceAllMapped(re, replace);
    }
    return out;
  }
}
