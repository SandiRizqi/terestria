import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import '../../models/geo_data_model.dart';
import '../../models/settings/gps_settings.dart';
import '../gps_settings_service.dart';
import '../gps/gps_filter_pipeline.dart';
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

  /// Pipeline pengolahan (akurasi/speed/static-noise/EMA/round) bersama dengan
  /// isolate background. Dibangun ulang dari [GpsSettings] runtime saat tracking
  /// dimulai. State smoothing/fix ada di dalam pipeline.
  GpsFilterPipeline _pipeline =
      GpsFilterPipeline(GpsFilterConfig.fromDefaults());

  /// Setelan GPS aktif (dipakai untuk timeout single-shot & pembulatan).
  GpsSettings _settings = GpsSettings.defaults();

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
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(
                seconds: GpsSettingsService().settings.getCurrentTimeoutSeconds),
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
        final maxAge = GpsSettingsService().settings.maxLastKnownAgeSeconds;
        if (!isLastKnownFresh(last.timestamp, DateTime.now(), maxAge)) {
          logError('❌ PhoneGpsService: last known position basi '
              '(${DateTime.now().difference(last.timestamp).inSeconds}s > '
              '${maxAge}s) — ditolak');
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

  double _roundCoord(double value) {
    final factor = _pipeline.config.coordinateRoundFactor;
    return (value * factor).round() / factor;
  }

  // ─── Continuous tracking ────────────────────────────────────────────────────

  /// Mulai tracking lokasi secara terus-menerus.
  ///
  /// Default seluruh parameter diambil dari [LocationConfig]. Override hanya
  /// jika perlu menyetel per-kasus.
  /// [distanceFilter] — minimum jarak (meter) sebelum update baru dikirim.
  /// [maxAccuracyMeters] — ambang buang reading SETELAH dapat fix bagus.
  Future<bool> startTracking({
    // bestForNavigation = akurasi tertinggi utk jalur (mirip tracker olahraga).
    // Single-shot getCurrentLocation tetap 'high' agar fix pertama cepat.
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    int? intervalMs,
    double? distanceFilter,
    double? maxAccuracyMeters, // dipertahankan utk kompat; pipeline yg menguasai
  }) async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return false;

      // Ambil setelan runtime & bangun ulang pipeline sesuai nilai user.
      _settings = GpsSettingsService().settings;
      final interval = intervalMs ?? _settings.trackingIntervalMs;
      final distFilter = distanceFilter ?? _settings.distanceFilterMeters;
      _pipeline = GpsFilterPipeline(_settings.toFilterConfig());

      // Cancel subscription yang ada
      await _locationSubscription?.cancel();

      // Buat LocationSettings sesuai platform untuk performa optimal
      final locationSettings =
          _buildLocationSettings(accuracy, distFilter, interval);

      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (position) => _handlePosition(position),
        onError: (error) {
          logError('❌ PhoneGpsService: Location stream error: $error');
        },
      );

      logDebug(
        '✅ PhoneGpsService: Tracking started '
        '(distanceFilter: ${distFilter}m, maxAccuracy: '
        '${_settings.maxAccuracyMeters}m, EMA α=${_settings.emaAlpha})',
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
    _pipeline.reset();
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

  /// Proses setiap position update lewat pipeline bersama, lalu push hasilnya.
  void _handlePosition(Position position) {
    final point = _pipeline.process(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      timestamp: position.timestamp,
      altitude: position.altitude,
    );
    if (point == null) return; // dibuang oleh filter
    _locationController.add(point);
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
