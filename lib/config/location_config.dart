/// Konfigurasi terpusat untuk semua parameter GPS / lokasi.
///
/// Semua nilai tuning (akurasi, smoothing, filter, timeout, dll) dikumpulkan
/// di sini agar mudah disetel ulang tanpa menyentuh logika service.
///
/// Dipakai oleh:
///  - [PhoneGpsService]           (foreground GPS)
///  - [LocationServiceV2]         (orchestrator + Emlid)
///  - [BackgroundTrackingService] (isolate background)
class LocationConfig {
  LocationConfig._();

  // ─── Filter akurasi ─────────────────────────────────────────────────────
  /// Reading dengan akurasi lebih buruk dari nilai ini (meter) DIBUANG —
  /// tetapi hanya SETELAH perangkat pernah mendapat fix bagus
  /// (lihat [acceptAllUntilGoodFix]).
  ///
  /// Dinaikkan dari 25 → 50 agar tidak membuang semua reading di area
  /// sinyal lemah (kebun, bawah kanopi, dekat bangunan).
  static const double maxAccuracyMeters = 50.0;

  /// Reading dengan akurasi <= nilai ini dianggap "fix bagus".
  /// Begitu satu fix bagus diterima, filter [maxAccuracyMeters] mulai aktif.
  static const double goodFixThresholdMeters = 20.0;

  /// Setelah sebanyak ini reading beruntun dibuang karena akurasi buruk,
  /// pipeline melonggar (terima reading lagi) sampai ada fix bagus baru —
  /// mencegah marker BEKU permanen saat sinyal memburuk (mis. bawah kanopi).
  static const int poorAccuracyDropsBeforeRelax = 3;

  /// Saat pipeline melonggar (setelah pernah dapat fix bagus lalu memburuk),
  /// reading tetap dibuang bila akurasinya di atas
  /// [maxAccuracyMeters] × nilai ini. Menahan fix "sampah" agar marker tak
  /// meloncat liar di bawah kanopi, tapi masih menerima fix jelek-wajar.
  static const double relaxedAccuracyMultiplier = 3.0;

  /// Bila true: sebelum ada fix bagus pertama, JANGAN buang reading apa pun
  /// (terima akurasi berapa pun) supaya marker langsung muncul & bergerak.
  static const bool acceptAllUntilGoodFix = true;

  // ─── EMA smoothing (foreground & background) ────────────────────────────
  /// Bobot EMA: new = alpha × reading + (1 - alpha) × previous.
  /// Lebih besar = lebih responsif (lag kecil). Dinaikkan 0.3 → 0.6.
  static const double emaAlpha = 0.6;

  /// Bila kecepatan di atas nilai ini (km/h), lewati EMA dan pakai koordinat
  /// mentah agar marker tidak tertinggal saat bergerak cepat.
  static const double emaBypassSpeedKmh = 30.0;

  // ─── Distance & static-noise filter ─────────────────────────────────────
  /// Minimum perpindahan (meter) sebelum geolocator mengirim update baru.
  static const double distanceFilterMeters = 2.0;

  /// Buang reading jika perpindahan dari titik terakhir < nilai ini (meter)
  /// dalam jendela [staticNoiseWindowMs]. Hanya aktif setelah fix bagus.
  static const double staticNoiseThresholdMeters = 0.5;

  /// Jendela waktu (ms) untuk static-noise filter.
  static const int staticNoiseWindowMs = 3600000; // 1 jam

  // ─── Speed filter ───────────────────────────────────────────────────────
  /// Buang reading dengan kecepatan tidak wajar (km/h) — spike GPS.
  static const double maxRealisticSpeedKmh = 180.0;

  // ─── Single-shot fix ────────────────────────────────────────────────────
  /// Batas waktu getCurrentPosition sebelum fallback ke last known position.
  static const Duration getCurrentTimeout = Duration(seconds: 12);

  /// Umur maksimum (detik) sebuah last-known-position agar boleh dipakai
  /// sebagai pengganti fix baru. Lebih tua dari ini → ditolak (bisa berjarak
  /// jam & kilometer dari posisi sebenarnya).
  static const int maxLastKnownAgeSeconds = 120;

  // ─── Tracking stream ────────────────────────────────────────────────────
  /// Interval minimal antar-update lokasi (ms).
  static const int trackingIntervalMs = 1000;

  // ─── Emlid ──────────────────────────────────────────────────────────────
  /// Emlid dianggap "stale" (tidak streaming) jika data terakhir lebih lama
  /// dari nilai ini. Saat stale, sistem fallback ke GPS phone.
  static const int emlidStaleSeconds = 10;

  // ─── Presisi koordinat ──────────────────────────────────────────────────
  /// Jumlah desimal pembulatan koordinat (6 ≈ presisi 11 cm).
  static const int coordinateDecimals = 6;

  /// Faktor pembulatan turunan dari [coordinateDecimals] (10^decimals).
  static const double coordinateRoundFactor = 1000000.0; // 10^6
}
