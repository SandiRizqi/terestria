import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import '../../models/geo_data_model.dart';
import '../../config/location_config.dart';
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
  /// isolate background. State smoothing/fix ada di dalam pipeline.
  final GpsFilterPipeline _pipeline =
      GpsFilterPipeline(GpsFilterConfig.fromDefaults());

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
      _pipeline.reset();

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
  /// [maxAccuracyMeters] dipertahankan untuk kompatibilitas signature; ambang
  /// akurasi sebenarnya kini dimiliki [GpsFilterPipeline].
  void _handlePosition(Position position, double maxAccuracyMeters) {
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
