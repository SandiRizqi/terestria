import 'dart:math' as math;

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
  final int poorAccuracyDropsBeforeRelax;
  final double relaxedAccuracyMultiplier;
  final double maxRealisticSpeedKmh;
  final double staticNoiseThresholdMeters;
  final int staticNoiseWindowMs;
  final double coordinateRoundFactor;
  // Parameter baru:
  final double outlierAccuracyK;
  final double stationaryAccuracyFactor;
  final bool warmupRequireGoodFix;
  final double kalmanQMetersPerSecond;
  final double stationarySpeedThresholdMps;
  final double kalmanReportedAccuracyFloorFactor;

  /// Rekam koordinat mentah (bukan hasil Kalman) — lihat
  /// [LocationConfig.recordRawPositions].
  final bool recordRawPositions;

  const GpsFilterConfig({
    required this.maxAccuracyMeters,
    required this.goodFixThresholdMeters,
    required this.acceptAllUntilGoodFix,
    required this.poorAccuracyDropsBeforeRelax,
    required this.relaxedAccuracyMultiplier,
    required this.maxRealisticSpeedKmh,
    required this.staticNoiseThresholdMeters,
    required this.staticNoiseWindowMs,
    required this.coordinateRoundFactor,
    required this.outlierAccuracyK,
    required this.stationaryAccuracyFactor,
    required this.warmupRequireGoodFix,
    required this.kalmanQMetersPerSecond,
    required this.stationarySpeedThresholdMps,
    required this.kalmanReportedAccuracyFloorFactor,
    this.recordRawPositions = LocationConfig.recordRawPositions,
  });

  /// Konfigurasi dari nilai default terpusat [LocationConfig].
  factory GpsFilterConfig.fromDefaults() => const GpsFilterConfig(
        maxAccuracyMeters: LocationConfig.maxAccuracyMeters,
        goodFixThresholdMeters: LocationConfig.goodFixThresholdMeters,
        acceptAllUntilGoodFix: LocationConfig.acceptAllUntilGoodFix,
        poorAccuracyDropsBeforeRelax:
            LocationConfig.poorAccuracyDropsBeforeRelax,
        relaxedAccuracyMultiplier: LocationConfig.relaxedAccuracyMultiplier,
        maxRealisticSpeedKmh: LocationConfig.maxRealisticSpeedKmh,
        staticNoiseThresholdMeters: LocationConfig.staticNoiseThresholdMeters,
        staticNoiseWindowMs: LocationConfig.staticNoiseWindowMs,
        coordinateRoundFactor: LocationConfig.coordinateRoundFactor,
        outlierAccuracyK: LocationConfig.outlierAccuracyK,
        stationaryAccuracyFactor: LocationConfig.stationaryAccuracyFactor,
        warmupRequireGoodFix: LocationConfig.warmupRequireGoodFix,
        kalmanQMetersPerSecond: LocationConfig.kalmanQMetersPerSecond,
        stationarySpeedThresholdMps:
            LocationConfig.stationarySpeedThresholdMps,
        kalmanReportedAccuracyFloorFactor:
            LocationConfig.kalmanReportedAccuracyFloorFactor,
        recordRawPositions: LocationConfig.recordRawPositions,
      );
}

/// Pipeline pengolahan reading GPS mentah menjadi [GeoPoint] siap pakai.
///
/// Memisahkan **display** vs **record**:
///  - SELALU mengeluarkan titik ter-smooth (Kalman) → marker mengikuti cepat.
///  - [GeoPoint.recordable] = true HANYA bila reading lolos semua gerbang ketat:
///    warm-up (sudah pernah fix bagus) + akurasi + anti-outlier (jarak/akurasi)
///    + bukan drift diam. Konsumen menampilkan marker selalu, tapi merekam ke
///    jalur hanya bila `recordable`.
///
/// Smoothing memakai Kalman skalar (akurasi = measurement-noise, Q = process-
/// noise m/s) sehingga reading buruk otomatis nyaris tak menggeser estimasi.
///
/// Menyimpan state (Kalman, titik terakhir DIREKAM, status fix). Satu instance
/// per sesi tracking. Dipakai bersama oleh foreground ([PhoneGpsService]) dan
/// isolate background agar pengolahan identik di kedua mode.
class GpsFilterPipeline {
  final GpsFilterConfig config;
  GpsFilterPipeline(this.config);

  // Titik terakhir yang DIREKAM (untuk gerbang outlier & stationary).
  double? _prevLat;
  double? _prevLon;
  double? _prevAcc;
  DateTime? _prevTime;

  // Status fix / warm-up.
  bool _hasGoodFix = false;
  bool _everHadGoodFix = false;
  int _consecutivePoorDrops = 0;

  // State Kalman skalar (posisi). _kVariance < 0 = belum diinisialisasi.
  double _kLat = 0;
  double _kLon = 0;
  double _kVariance = -1;
  DateTime? _kTime;

  bool get hasGoodFix => _hasGoodFix;
  bool get everHadGoodFix => _everHadGoodFix;

  void reset() {
    _prevLat = null;
    _prevLon = null;
    _prevAcc = null;
    _prevTime = null;
    _hasGoodFix = false;
    _everHadGoodFix = false;
    _consecutivePoorDrops = 0;
    _kVariance = -1;
    _kTime = null;
  }

  /// Proses satu reading. Mengembalikan [GeoPoint] ter-smooth untuk DISPLAY
  /// (dengan [GeoPoint.recordable] menandai apakah aman direkam ke jalur), atau
  /// `null` bila reading benar-benar tak terpakai. [speed] dalam m/s (`<0` =
  /// tidak diketahui).
  GeoPoint? process({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required DateTime timestamp,
    double? altitude,
  }) {
    final double acc =
        (accuracy.isFinite && accuracy > 0) ? accuracy : 9999.0;

    // Tandai fix bagus → aktifkan filter penuh & buka warm-up.
    if (acc <= config.goodFixThresholdMeters) {
      _hasGoodFix = true;
      _everHadGoodFix = true;
      _consecutivePoorDrops = 0;
    }

    // ── Kalman smoothing (SELALU, untuk display) ────────────────────────────
    final (kLat, kLon) = _kalman(latitude, longitude, acc, timestamp);

    // ── Keputusan recordable ────────────────────────────────────────────────
    bool recordable = true;

    // Warm-up: rekam hanya setelah fix bagus pertama.
    if (config.warmupRequireGoodFix && !_everHadGoodFix) {
      recordable = false;
    }

    // Filter akurasi untuk REKAM (adaptif: melonggar saat sinyal memburuk agar
    // tak beku permanen di bawah kanopi, tapi tetap tolak fix sampah).
    final double recCeil = _hasGoodFix
        ? config.maxAccuracyMeters
        : config.maxAccuracyMeters * config.relaxedAccuracyMultiplier;
    if (acc > recCeil) {
      recordable = false;
      if (_hasGoodFix) {
        _consecutivePoorDrops++;
        if (_consecutivePoorDrops >= config.poorAccuracyDropsBeforeRelax) {
          _hasGoodFix = false;
        }
      }
    } else {
      _consecutivePoorDrops = 0;
    }

    // Gerbang anti-outlier + stationary — SELALU dihitung dari titik terakhir
    // yang direkam (bukan speed OS), sehingga teleport & drift diam tertahan.
    double? segSpeedKmh;
    if (recordable && _prevLat != null && _prevTime != null) {
      final dtSec = timestamp.difference(_prevTime!).inMilliseconds / 1000.0;
      final jump = _haversineMeters(_prevLat!, _prevLon!, latitude, longitude);
      if (dtSec > 0) segSpeedKmh = jump / dtSec * 3.6;

      // Anti-outlier: tolak lompatan yang melebihi (kecepatan wajar × dt) plus
      // toleransi akurasi (makin buruk akurasi, makin longgar). dt yang membesar
      // saat menolak → gerbang melonggar → pulih bila memang berpindah nyata.
      final maxJump = (config.maxRealisticSpeedKmh / 3.6) * dtSec +
          config.outlierAccuracyK * ((_prevAcc ?? acc) + acc);
      if (jump > maxJump) recordable = false;

      // Stationary hold: tahan dari rekaman bila hampir tak bergerak (marker
      // tetap tampil). Radius diam menyesuaikan akurasi. TAPI hanya ditahan
      // bila OS tak melaporkan gerak jelas (doppler) — agar jalan lambat di
      // area akurasi buruk (radius besar) tak ikut terbuang. speed OS < 0
      // (tak diketahui) → jatuh ke keputusan jarak saja.
      final stationaryRadius = math.max(config.staticNoiseThresholdMeters,
          config.stationaryAccuracyFactor * acc);
      final movingByOs = speed >= config.stationarySpeedThresholdMps;
      if (jump < stationaryRadius && !movingByOs) recordable = false;
    }

    // Perbarui titik terakhir DIREKAM hanya saat recordable.
    if (recordable) {
      _prevLat = latitude;
      _prevLon = longitude;
      _prevAcc = acc;
      _prevTime = timestamp;
    }

    // Speed: pakai OS bila diketahui (>=0), jika tidak turunkan dari segmen.
    final double? outSpeedKmh = speed >= 0 ? speed * 3.6 : segSpeedKmh;
    final double? speedRounded =
        outSpeedKmh != null ? (outSpeedKmh * 10).round() / 10.0 : null;

    // Akurasi laporan = std posterior Kalman, DILANTAI relatif akurasi mentah.
    // Std Kalman bisa terlalu optimistis (error GPS berkorelasi), jadi ring tak
    // boleh menampilkan lingkaran yang menyesatkan kecil.
    final double kStd = _kVariance > 0 ? math.sqrt(_kVariance) : acc;
    final double floored =
        math.max(kStd, config.kalmanReportedAccuracyFloorFactor * acc);
    final double reportedAcc = floored.isFinite ? floored : acc;

    final keepRaw = recordable && config.recordRawPositions;
    return GeoPoint(
      latitude: _round(kLat),
      longitude: _round(kLon),
      altitude: altitude,
      accuracy: reportedAcc,
      speed: speedRounded,
      timestamp: timestamp,
      recordable: recordable,
      rawLatitude: keepRaw ? _round(latitude) : null,
      rawLongitude: keepRaw ? _round(longitude) : null,
      rawAccuracy: keepRaw ? acc : null,
    );
  }

  /// Kalman skalar untuk posisi (lat/lon). Akurasi = measurement-noise (meter),
  /// Q = process-noise (m/s). Mengembalikan (lat, lon) ter-smooth.
  (double, double) _kalman(double lat, double lon, double acc, DateTime ts) {
    final double accM = acc < 1.0 ? 1.0 : acc;
    if (_kVariance < 0) {
      _kLat = lat;
      _kLon = lon;
      _kVariance = accM * accM;
      _kTime = ts;
      return (_kLat, _kLon);
    }
    if (_kTime != null) {
      final dt = ts.difference(_kTime!).inMilliseconds / 1000.0;
      if (dt > 0) {
        final q = config.kalmanQMetersPerSecond;
        _kVariance += dt * q * q;
        _kTime = ts;
      }
    }
    final k = _kVariance / (_kVariance + accM * accM);
    _kLat += k * (lat - _kLat);
    _kLon += k * (lon - _kLon);
    _kVariance = (1 - k) * _kVariance;
    return (_kLat, _kLon);
  }

  double _round(double value) =>
      (value * config.coordinateRoundFactor).round() /
      config.coordinateRoundFactor;

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    const toRad = 3.141592653589793 / 180;
    final dLat = (lat2 - lat1) * toRad;
    final dLon = (lon2 - lon1) * toRad;
    final sLat = math.sin(dLat / 2);
    final sLon = math.sin(dLon / 2);
    final a = sLat * sLat +
        math.cos(lat1 * toRad) * math.cos(lat2 * toRad) * sLon * sLon;
    return r * 2 * math.asin(math.sqrt(a));
  }
}
