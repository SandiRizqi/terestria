import 'dart:async';
import 'dart:io';
import 'dart:math' show cos, asin, sqrt;
import 'package:geolocator/geolocator.dart';
import '../../models/geo_data_model.dart';

/// Service untuk mendapatkan lokasi dari GPS phone.
/// Menggunakan geolocator dengan:
/// - distanceFilter: hanya update jika bergerak minimal [_defaultDistanceFilter] meter
/// - Accuracy filter: abaikan reading dengan akurasi > [_maxAccuracyMeters]
/// - EMA smoothing: ratakan noise koordinat sebelum dikirim ke stream
class PhoneGpsService {
  StreamSubscription<Position>? _locationSubscription;
  final StreamController<GeoPoint> _locationController =
      StreamController<GeoPoint>.broadcast();

  // ─── Tuning constants ───────────────────────────────────────────────────────
  /// Minimum perpindahan (meter) sebelum update baru dikirim ke stream.
  /// Menyaring noise GPS saat diam tanpa mempengaruhi kecepatan tinggi.
  static const double _defaultDistanceFilter = 2.0;

  /// Abaikan reading GPS dengan akurasi lebih buruk dari nilai ini (meter).
  static const double _maxAccuracyMeters = 25.0;

  /// Weight untuk EMA smoothing. Lebih kecil = lebih smooth tapi lebih lambat respons.
  /// 0.3 = smooth; 0.5 = balance; 1.0 = no smoothing (raw)
  static const double _emaAlpha = 0.3;
  // ────────────────────────────────────────────────────────────────────────────

  // EMA state — di-reset saat tracking dimulai atau dihentikan
  double? _smoothLat;
  double? _smoothLon;

  // State for static-noise filter
  double? _prevLat;
  double? _prevLon;
  DateTime? _prevTime;

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
      print('❌ PhoneGpsService: Location service not enabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      print('❌ PhoneGpsService: Permission not granted ($permission)');
      return false;
    }

    print('✅ PhoneGpsService: Permission granted ($permission)');
    return true;
  }

  // ─── Single-shot location ───────────────────────────────────────────────────

  Future<GeoPoint?> getCurrentLocation() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final speedMs = position.speed;
      return GeoPoint(
        latitude: (position.latitude * 1000000).round() / 1000000,
        longitude: (position.longitude * 1000000).round() / 1000000,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: speedMs >= 0 ? (speedMs * 3.6 * 10).round() / 10.0 : null,
        timestamp: position.timestamp,
      );
    } catch (e) {
      print('❌ PhoneGpsService: Error getting current location: $e');
      return null;
    }
  }

  // ─── Continuous tracking ────────────────────────────────────────────────────

  /// Mulai tracking lokasi secara terus-menerus.
  ///
  /// [distanceFilter] — minimum jarak (meter) sebelum update baru dikirim.
  ///   Default 2.0m: cukup untuk saring noise diam, responsif di kecepatan tinggi.
  /// [maxAccuracyMeters] — abaikan reading dengan akurasi lebih buruk dari nilai ini.
  Future<bool> startTracking({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int intervalMs = 1000,
    double distanceFilter = _defaultDistanceFilter,
    double maxAccuracyMeters = _maxAccuracyMeters,
  }) async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return false;

      // Reset EMA saat tracking baru dimulai
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
          print('❌ PhoneGpsService: Location stream error: $error');
        },
      );

      print(
        '✅ PhoneGpsService: Tracking started '
        '(distanceFilter: ${distanceFilter}m, maxAccuracy: ${maxAccuracyMeters}m, EMA α=$_emaAlpha)',
      );
      return true;
    } catch (e) {
      print('❌ PhoneGpsService: Error starting tracking: $e');
      return false;
    }
  }

  Future<void> stopTracking() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _resetSmoothing();
    print('⏹️ PhoneGpsService: Tracking stopped');
  }

  /// Background mode tidak lagi diperlukan di sini karena background tracking
  /// ditangani sepenuhnya oleh BackgroundTrackingService + flutter_background_service.
  Future<void> enableBackgroundMode(bool enable) async {
    print('ℹ️ PhoneGpsService: enableBackgroundMode() tidak dipakai — '
        'gunakan BackgroundTrackingService untuk background tracking');
  }

  void dispose() {
    _locationSubscription?.cancel();
    _locationController.close();
    print('🗑️ PhoneGpsService: Disposed');
  }

  // ─── Internal helpers ───────────────────────────────────────────────────────

  /// Proses setiap position update: filter akurasi → speed → static-noise → EMA → round → push.
  void _handlePosition(Position position, double maxAccuracyMeters) {
    // Filter 1: Accuracy filter
    if (position.accuracy > maxAccuracyMeters) {
      print(
        '⚠️ PhoneGpsService: Skip — akurasi buruk '
        '(${position.accuracy.toStringAsFixed(1)}m > ${maxAccuracyMeters}m)',
      );
      return;
    }

    // Filter 2: Speed filter — buang spike GPS (>180 km/h mustahil untuk kendaraan kebun)
    final speedMs = position.speed;
    if (speedMs >= 0 && speedMs * 3.6 > 180.0) {
      print('⚠️ PhoneGpsService: Skip — kecepatan tidak wajar (${(speedMs * 3.6).toStringAsFixed(1)} km/h)');
      return;
    }

    // Filter 3: Static-noise filter — buang jika hampir tidak bergerak dalam <1 jam
    final now = position.timestamp;
    if (_prevLat != null && _prevLon != null && _prevTime != null) {
      final dist = _haversineMeters(_prevLat!, _prevLon!, position.latitude, position.longitude);
      final deltaMs = now.difference(_prevTime!).inMilliseconds;
      if (dist < 0.5 && deltaMs < 3600000) {
        print('⚠️ PhoneGpsService: Skip — posisi statis (${dist.toStringAsFixed(2)}m dalam ${deltaMs}ms)');
        return;
      }
    }
    _prevLat = position.latitude;
    _prevLon = position.longitude;
    _prevTime = now;

    // Filter 4: EMA smoothing
    final (smoothedLat, smoothedLon) =
        _applyEma(position.latitude, position.longitude);

    // Round to 6 decimal places (~11 cm precision)
    final lat = (smoothedLat * 1000000).round() / 1000000;
    final lon = (smoothedLon * 1000000).round() / 1000000;
    final speedKmh = speedMs >= 0 ? (speedMs * 3.6 * 10).round() / 10.0 : null;

    final point = GeoPoint(
      latitude: lat,
      longitude: lon,
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: speedKmh,
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
      _smoothLat = _emaAlpha * lat + (1.0 - _emaAlpha) * _smoothLat!;
      _smoothLon = _emaAlpha * lon + (1.0 - _emaAlpha) * _smoothLon!;
    }
    return (_smoothLat!, _smoothLon!);
  }

  void _resetSmoothing() {
    _smoothLat = null;
    _smoothLon = null;
    _prevLat = null;
    _prevLon = null;
    _prevTime = null;
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
