import 'dart:math' show cos, asin, sqrt;

import '../../config/location_config.dart';
import '../../models/geo_data_model.dart';

/// Parameter tuning untuk [GpsFilterPipeline].
///
/// Nilai default berasal dari [LocationConfig]; saat fitur GPS Settings aktif,
/// nilai ini dibangun dari `GpsSettings` (runtime) — pipeline tidak pernah
/// membaca [LocationConfig] secara langsung.
class GpsFilterConfig {
  final double maxAccuracyMeters;
  final double goodFixThresholdMeters;
  final bool acceptAllUntilGoodFix;
  final double maxRealisticSpeedKmh;
  final double staticNoiseThresholdMeters;
  final int staticNoiseWindowMs;
  final double emaAlpha;
  final double emaBypassSpeedKmh;
  final double coordinateRoundFactor;

  const GpsFilterConfig({
    required this.maxAccuracyMeters,
    required this.goodFixThresholdMeters,
    required this.acceptAllUntilGoodFix,
    required this.maxRealisticSpeedKmh,
    required this.staticNoiseThresholdMeters,
    required this.staticNoiseWindowMs,
    required this.emaAlpha,
    required this.emaBypassSpeedKmh,
    required this.coordinateRoundFactor,
  });

  /// Konfigurasi dari nilai default terpusat [LocationConfig].
  factory GpsFilterConfig.fromDefaults() => const GpsFilterConfig(
        maxAccuracyMeters: LocationConfig.maxAccuracyMeters,
        goodFixThresholdMeters: LocationConfig.goodFixThresholdMeters,
        acceptAllUntilGoodFix: LocationConfig.acceptAllUntilGoodFix,
        maxRealisticSpeedKmh: LocationConfig.maxRealisticSpeedKmh,
        staticNoiseThresholdMeters: LocationConfig.staticNoiseThresholdMeters,
        staticNoiseWindowMs: LocationConfig.staticNoiseWindowMs,
        emaAlpha: LocationConfig.emaAlpha,
        emaBypassSpeedKmh: LocationConfig.emaBypassSpeedKmh,
        coordinateRoundFactor: LocationConfig.coordinateRoundFactor,
      );
}

/// Pipeline pengolahan reading GPS mentah menjadi [GeoPoint] siap pakai.
///
/// Urutan: filter akurasi (adaptif) → filter kecepatan → filter static-noise →
/// EMA smoothing → pembulatan. Menyimpan state (EMA, titik sebelumnya, status
/// fix bagus) sehingga dipakai satu instance per sesi tracking.
///
/// Dipakai bersama oleh foreground ([PhoneGpsService]) dan isolate background
/// agar pengolahan identik di kedua mode.
class GpsFilterPipeline {
  final GpsFilterConfig config;
  GpsFilterPipeline(this.config);

  double? _smoothLat;
  double? _smoothLon;
  double? _prevLat;
  double? _prevLon;
  DateTime? _prevTime;
  bool _hasGoodFix = false;

  bool get hasGoodFix => _hasGoodFix;

  void reset() {
    _smoothLat = null;
    _smoothLon = null;
    _prevLat = null;
    _prevLon = null;
    _prevTime = null;
    _hasGoodFix = false;
  }

  /// Proses satu reading. Mengembalikan [GeoPoint] terfilter, atau `null` bila
  /// reading dibuang. [speed] dalam m/s (`<0` = tidak diketahui).
  GeoPoint? process({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required DateTime timestamp,
    double? altitude,
  }) {
    // Tandai fix bagus begitu akurasi cukup baik (mengaktifkan filter penuh).
    if (accuracy <= config.goodFixThresholdMeters) {
      _hasGoodFix = true;
    }

    // Filter 1: Accuracy filter ADAPTIF. Sebelum fix bagus pertama (dan bila
    // acceptAllUntilGoodFix), jangan buang reading apa pun.
    final accuracyFilterActive = _hasGoodFix || !config.acceptAllUntilGoodFix;
    if (accuracyFilterActive && accuracy > config.maxAccuracyMeters) {
      return null;
    }

    // Filter 2: Speed filter — buang spike GPS (kecepatan tidak wajar).
    final speedKmh = speed >= 0 ? speed * 3.6 : -1.0;
    if (speedKmh > config.maxRealisticSpeedKmh) {
      return null;
    }

    // Filter 3: Static-noise — buang bila hampir tidak bergerak. Hanya aktif
    // setelah fix bagus agar tidak menahan update awal.
    if (_hasGoodFix &&
        _prevLat != null &&
        _prevLon != null &&
        _prevTime != null) {
      final dist = _haversineMeters(_prevLat!, _prevLon!, latitude, longitude);
      final deltaMs = timestamp.difference(_prevTime!).inMilliseconds;
      if (dist < config.staticNoiseThresholdMeters &&
          deltaMs < config.staticNoiseWindowMs) {
        return null;
      }
    }
    _prevLat = latitude;
    _prevLon = longitude;
    _prevTime = timestamp;

    // Filter 4: EMA smoothing — dilewati saat bergerak cepat agar tidak lag.
    final double outLat;
    final double outLon;
    if (speedKmh > config.emaBypassSpeedKmh) {
      _smoothLat = latitude;
      _smoothLon = longitude;
      outLat = latitude;
      outLon = longitude;
    } else {
      final (sLat, sLon) = _applyEma(latitude, longitude);
      outLat = sLat;
      outLon = sLon;
    }

    final speedRounded =
        speed >= 0 ? (speed * 3.6 * 10).round() / 10.0 : null;

    return GeoPoint(
      latitude: _round(outLat),
      longitude: _round(outLon),
      altitude: altitude,
      accuracy: accuracy,
      speed: speedRounded,
      timestamp: timestamp,
    );
  }

  (double, double) _applyEma(double lat, double lon) {
    if (_smoothLat == null || _smoothLon == null) {
      _smoothLat = lat;
      _smoothLon = lon;
    } else {
      final a = config.emaAlpha;
      _smoothLat = a * lat + (1.0 - a) * _smoothLat!;
      _smoothLon = a * lon + (1.0 - a) * _smoothLon!;
    }
    return (_smoothLat!, _smoothLon!);
  }

  double _round(double value) =>
      (value * config.coordinateRoundFactor).round() /
      config.coordinateRoundFactor;

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    const toRad = 3.141592653589793 / 180;
    final dLat = (lat2 - lat1) * toRad;
    final dLon = (lon2 - lon1) * toRad;
    final a = (dLat / 2) * (dLat / 2) +
        cos(lat1 * toRad) * cos(lat2 * toRad) * (dLon / 2) * (dLon / 2);
    return r * 2 * asin(sqrt(a));
  }
}
