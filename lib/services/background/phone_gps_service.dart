import 'dart:async';
import 'dart:io';
import 'dart:math' show cos, asin, sqrt;
import 'package:geolocator/geolocator.dart';
import '../../models/geo_data_model.dart';
import '../../config/location_config.dart';
import '../../utils/app_logger.dart';

/// True bila [fixTime] belum lebih tua dari [maxAgeSec] detik terhadap [now].
/// Timestamp masa depan (clock skew) dianggap fresh.
bool isLastKnownFresh(DateTime fixTime, DateTime now, int maxAgeSec) =>
    now.difference(fixTime).inSeconds <= maxAgeSec;

/// Service untuk mendapatkan lokasi dari GPS phone.
/// Menggunakan geolocator dengan:
/// - distanceFilter: hanya update jika bergerak minimal
///   [LocationConfig.distanceFilterMeters] meter
/// - Accuracy filter ADAPTIF: sebelum dapat fix bagus, terima semua reading;
///   setelahnya buang reading dengan akurasi > [LocationConfig.maxAccuracyMeters]
/// - EMA smoothing: ratakan noise koordinat sebelum dikirim ke stream
///
/// Semua nilai tuning terpusat di [LocationConfig].
class PhoneGpsService {
  StreamSubscription<Position>? _locationSubscription;
  final StreamController<GeoPoint> _locationController =
      StreamController<GeoPoint>.broadcast();

  // EMA state — di-reset saat tracking dimulai atau dihentikan
  double? _smoothLat;
  double? _smoothLon;

  // State for static-noise filter
  double? _prevLat;
  double? _prevLon;
  DateTime? _prevTime;

  /// True setelah perangkat mendapat fix dengan akurasi <=
  /// [LocationConfig.goodFixThresholdMeters]. Sebelum itu, filter akurasi &
  /// static-noise dilonggarkan agar marker langsung muncul & bergerak di
  /// area sinyal lemah.
  bool _hasGoodFix = false;

  Stream<GeoPoint> get locationStream => _locationController.stream;

  // ─── Permission & Service ───────────────────────────────────────────────────

  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  Future<bool> checkAndRequestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      logError('❌ PhoneGpsService: Location service not enabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      logError('❌ PhoneGpsService: Permission not granted ($permission)');
      return false;
    }

    logDebug('✅ PhoneGpsService: Permission granted ($permission)');
    return true;
  }

  // ─── Single-shot location ───────────────────────────────────────────────────

  Future<GeoPoint?> getCurrentLocation() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return null;

      Position position;
      try {
        // Coba dapatkan fix baru dengan batas waktu agar tidak menggantung
        // di area sinyal lemah / cold start.
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: LocationConfig.getCurrentTimeout,
          ),
        );
      } catch (e) {
        // Timeout / gagal → fallback ke posisi terakhir yang diketahui
        // supaya UI tidak ngadat menunggu.
        logDebug('⚠️ PhoneGpsService: getCurrentPosition gagal ($e), '
            'fallback ke getLastKnownPosition');
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) {
          logError('❌ PhoneGpsService: Tidak ada last known position');
          return null;
        }
        // Tolak fix basi — bisa berjarak jam & kilometer dari posisi nyata.
        if (!isLastKnownFresh(
          last.timestamp,
          DateTime.now(),
          LocationConfig.maxLastKnownAgeSeconds,
        )) {
          logError('❌ PhoneGpsService: last known position basi '
              '(${DateTime.now().difference(last.timestamp).inSeconds}s > '
              '${LocationConfig.maxLastKnownAgeSeconds}s) — ditolak');
          return null;
        }
        position = last;
      }

      return _toGeoPoint(position);
    } catch (e) {
      logError('❌ PhoneGpsService: Error getting current location: $e');
      return null;
    }
  }

  /// Konversi [Position] geolocator → [GeoPoint] dengan pembulatan koordinat.
  GeoPoint _toGeoPoint(Position position) {
    final speedMs = position.speed;
    return GeoPoint(
      latitude: _roundCoord(position.latitude),
      longitude: _roundCoord(position.longitude),
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: speedMs >= 0 ? (speedMs * 3.6 * 10).round() / 10.0 : null,
      timestamp: position.timestamp,
    );
  }

  double _roundCoord(double value) =>
      (value * LocationConfig.coordinateRoundFactor).round() /
      LocationConfig.coordinateRoundFactor;

  // ─── Continuous tracking ────────────────────────────────────────────────────

  /// Mulai tracking lokasi secara terus-menerus.
  ///
  /// Default seluruh parameter diambil dari [LocationConfig]. Override hanya
  /// jika perlu menyetel per-kasus.
  /// [distanceFilter] — minimum jarak (meter) sebelum update baru dikirim.
  /// [maxAccuracyMeters] — ambang buang reading SETELAH dapat fix bagus.
  Future<bool> startTracking({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int intervalMs = LocationConfig.trackingIntervalMs,
    double distanceFilter = LocationConfig.distanceFilterMeters,
    double maxAccuracyMeters = LocationConfig.maxAccuracyMeters,
  }) async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return false;

      // Reset EMA & status fix saat tracking baru dimulai
      _resetSmoothing();

      // Cancel subscription yang ada
      await _locationSubscription?.cancel();

      // Buat LocationSettings sesuai platform untuk performa optimal
      final locationSettings = _buildLocationSettings(accuracy, distanceFilter, intervalMs);

      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (position) => _handlePosition(position, maxAccuracyMeters),
        onError: (error) {
          logError('❌ PhoneGpsService: Location stream error: $error');
        },
      );

      logDebug(
        '✅ PhoneGpsService: Tracking started '
        '(distanceFilter: ${distanceFilter}m, maxAccuracy: ${maxAccuracyMeters}m, '
        'EMA α=${LocationConfig.emaAlpha})',
      );
      return true;
    } catch (e) {
      logError('❌ PhoneGpsService: Error starting tracking: $e');
      return false;
    }
  }

  Future<void> stopTracking() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _resetSmoothing();
    logDebug('⏹️ PhoneGpsService: Tracking stopped');
  }

  /// Background mode tidak lagi diperlukan di sini karena background tracking
  /// ditangani sepenuhnya oleh BackgroundTrackingService + flutter_background_service.
  Future<void> enableBackgroundMode(bool enable) async {
    logDebug('ℹ️ PhoneGpsService: enableBackgroundMode() tidak dipakai — '
        'gunakan BackgroundTrackingService untuk background tracking');
  }

  void dispose() {
    _locationSubscription?.cancel();
    _locationController.close();
    logDebug('🗑️ PhoneGpsService: Disposed');
  }

  // ─── Internal helpers ───────────────────────────────────────────────────────

  /// Proses setiap position update: filter akurasi (adaptif) → speed →
  /// static-noise → EMA → round → push.
  void _handlePosition(Position position, double maxAccuracyMeters) {
    // Tandai fix bagus begitu akurasi cukup baik (mengaktifkan filter penuh).
    if (position.accuracy <= LocationConfig.goodFixThresholdMeters) {
      _hasGoodFix = true;
    }

    // Filter 1: Accuracy filter ADAPTIF.
    // Sebelum dapat fix bagus pertama (acceptAllUntilGoodFix), JANGAN buang
    // reading apa pun supaya marker langsung muncul & bergerak di sinyal lemah.
    final accuracyFilterActive =
        _hasGoodFix || !LocationConfig.acceptAllUntilGoodFix;
    if (accuracyFilterActive && position.accuracy > maxAccuracyMeters) {
      logDebug(
        '⚠️ PhoneGpsService: Skip — akurasi buruk '
        '(${position.accuracy.toStringAsFixed(1)}m > ${maxAccuracyMeters}m)',
      );
      return;
    }

    // Filter 2: Speed filter — buang spike GPS (kecepatan tidak wajar).
    final speedMs = position.speed;
    final speedKmh = speedMs >= 0 ? speedMs * 3.6 : -1.0;
    if (speedKmh > LocationConfig.maxRealisticSpeedKmh) {
      logDebug('⚠️ PhoneGpsService: Skip — kecepatan tidak wajar '
          '(${speedKmh.toStringAsFixed(1)} km/h)');
      return;
    }

    // Filter 3: Static-noise filter — buang jika hampir tidak bergerak.
    // Hanya aktif setelah fix bagus, agar tidak menahan update awal.
    final now = position.timestamp;
    if (_hasGoodFix &&
        _prevLat != null &&
        _prevLon != null &&
        _prevTime != null) {
      final dist = _haversineMeters(
          _prevLat!, _prevLon!, position.latitude, position.longitude);
      final deltaMs = now.difference(_prevTime!).inMilliseconds;
      if (dist < LocationConfig.staticNoiseThresholdMeters &&
          deltaMs < LocationConfig.staticNoiseWindowMs) {
        logDebug('⚠️ PhoneGpsService: Skip — posisi statis '
            '(${dist.toStringAsFixed(2)}m dalam ${deltaMs}ms)');
        return;
      }
    }
    _prevLat = position.latitude;
    _prevLon = position.longitude;
    _prevTime = now;

    // Filter 4: EMA smoothing — dilewati saat bergerak cepat agar tidak lag.
    final double outLat;
    final double outLon;
    if (speedKmh > LocationConfig.emaBypassSpeedKmh) {
      // Gerak cepat: pakai koordinat mentah, tapi tetap simpan sebagai basis EMA.
      _smoothLat = position.latitude;
      _smoothLon = position.longitude;
      outLat = position.latitude;
      outLon = position.longitude;
    } else {
      final (smoothedLat, smoothedLon) =
          _applyEma(position.latitude, position.longitude);
      outLat = smoothedLat;
      outLon = smoothedLon;
    }

    final speedRounded =
        speedMs >= 0 ? (speedMs * 3.6 * 10).round() / 10.0 : null;

    final point = GeoPoint(
      latitude: _roundCoord(outLat),
      longitude: _roundCoord(outLon),
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: speedRounded,
      timestamp: position.timestamp,
    );

    _locationController.add(point);
  }

  /// Exponential Moving Average: new = α × reading + (1−α) × previous
  /// Returns (smoothedLat, smoothedLon).
  (double, double) _applyEma(double lat, double lon) {
    if (_smoothLat == null || _smoothLon == null) {
      // Reading pertama — inisialisasi tanpa smoothing agar langsung responsif
      _smoothLat = lat;
      _smoothLon = lon;
    } else {
      const alpha = LocationConfig.emaAlpha;
      _smoothLat = alpha * lat + (1.0 - alpha) * _smoothLat!;
      _smoothLon = alpha * lon + (1.0 - alpha) * _smoothLon!;
    }
    return (_smoothLat!, _smoothLon!);
  }

  void _resetSmoothing() {
    _smoothLat = null;
    _smoothLon = null;
    _prevLat = null;
    _prevLon = null;
    _prevTime = null;
    _hasGoodFix = false;
  }

  /// Haversine distance in meters between two lat/lon points.
  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    const toRad = 3.141592653589793 / 180;
    final dLat = (lat2 - lat1) * toRad;
    final dLon = (lon2 - lon1) * toRad;
    final a = (dLat / 2) * (dLat / 2) +
        cos(lat1 * toRad) * cos(lat2 * toRad) * (dLon / 2) * (dLon / 2);
    return r * 2 * asin(sqrt(a));
  }

  /// Buat LocationSettings yang dioptimasi per platform.
  LocationSettings _buildLocationSettings(
    LocationAccuracy accuracy,
    double distanceFilter,
    int intervalMs,
  ) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter.toInt(),
        intervalDuration: Duration(milliseconds: intervalMs),
        // Tidak ada foreground notification — ini untuk foreground tracking
        forceLocationManager: false,
      );
    } else if (Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter.toInt(),
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
        // Background indicator tidak perlu di sini — background via BackgroundTrackingService
        showBackgroundLocationIndicator: false,
      );
    } else {
      return LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter.toInt(),
      );
    }
  }
}
