import 'dart:math' show pow;

import '../../config/location_config.dart';
import '../../services/gps/gps_filter_pipeline.dart';

/// Nilai tuning GPS yang bisa disetel user (runtime), menggantikan konstanta
/// [LocationConfig] sebagai sumber kebenaran saat berjalan. Model murni Dart
/// (tanpa Flutter) agar aman dipakai di isolate background & mudah dites.
///
/// Setiap field punya rentang `*_min` / `*_max`; nilai selalu di-clamp saat
/// dibaca dari JSON supaya tak ada setelan yang merusak tracking.
class GpsSettings {
  // ─── Rentang valid ───────────────────────────────────────────────────────
  static const double maxAccuracyMin = 5, maxAccuracyMax = 200;
  static const double goodFixMin = 3, goodFixMax = 50;
  static const int poorDropsMin = 1, poorDropsMax = 20;
  static const double relaxedMultMin = 1, relaxedMultMax = 6;
  static const double distanceFilterMin = 0, distanceFilterMax = 50;
  static const double staticNoiseMin = 0, staticNoiseMax = 10;
  static const int staticWindowMin = 0, staticWindowMax = 3600;
  static const double maxSpeedMin = 30, maxSpeedMax = 400;
  static const int trackingIntervalMin = 200, trackingIntervalMax = 10000;
  static const int getCurrentTimeoutMin = 3, getCurrentTimeoutMax = 60;
  static const int emlidStaleMin = 2, emlidStaleMax = 60;
  static const int lastKnownAgeMin = 5, lastKnownAgeMax = 600;
  static const int coordinateDecimalsMin = 4, coordinateDecimalsMax = 8;
  static const double outlierKMin = 0, outlierKMax = 10;
  static const double stationaryFactorMin = 0, stationaryFactorMax = 5;
  static const double kalmanQMin = 0.1, kalmanQMax = 20;

  // ─── Field ───────────────────────────────────────────────────────────────
  final double maxAccuracyMeters;
  final double goodFixThresholdMeters;
  final bool acceptAllUntilGoodFix;
  final int poorAccuracyDropsBeforeRelax;
  final double relaxedAccuracyMultiplier;
  final double distanceFilterMeters;
  final double staticNoiseThresholdMeters;
  final int staticNoiseWindowSeconds;
  final double maxRealisticSpeedKmh;
  final int trackingIntervalMs;
  final int getCurrentTimeoutSeconds;
  final int emlidStaleSeconds;
  final int maxLastKnownAgeSeconds;
  final int coordinateDecimals;
  // Anti-outlier / stationary / warm-up / Kalman.
  final double outlierAccuracyK;
  final double stationaryAccuracyFactor;
  final bool warmupRequireGoodFix;
  final double kalmanQMetersPerSecond;

  const GpsSettings({
    required this.maxAccuracyMeters,
    required this.goodFixThresholdMeters,
    required this.acceptAllUntilGoodFix,
    required this.poorAccuracyDropsBeforeRelax,
    required this.relaxedAccuracyMultiplier,
    required this.distanceFilterMeters,
    required this.staticNoiseThresholdMeters,
    required this.staticNoiseWindowSeconds,
    required this.maxRealisticSpeedKmh,
    required this.trackingIntervalMs,
    required this.getCurrentTimeoutSeconds,
    required this.emlidStaleSeconds,
    required this.maxLastKnownAgeSeconds,
    required this.coordinateDecimals,
    required this.outlierAccuracyK,
    required this.stationaryAccuracyFactor,
    required this.warmupRequireGoodFix,
    required this.kalmanQMetersPerSecond,
  });

  /// Default dari konstanta terpusat [LocationConfig].
  factory GpsSettings.defaults() => GpsSettings(
        maxAccuracyMeters: LocationConfig.maxAccuracyMeters,
        goodFixThresholdMeters: LocationConfig.goodFixThresholdMeters,
        acceptAllUntilGoodFix: LocationConfig.acceptAllUntilGoodFix,
        poorAccuracyDropsBeforeRelax:
            LocationConfig.poorAccuracyDropsBeforeRelax,
        relaxedAccuracyMultiplier: LocationConfig.relaxedAccuracyMultiplier,
        distanceFilterMeters: LocationConfig.distanceFilterMeters,
        staticNoiseThresholdMeters: LocationConfig.staticNoiseThresholdMeters,
        staticNoiseWindowSeconds: LocationConfig.staticNoiseWindowMs ~/ 1000,
        maxRealisticSpeedKmh: LocationConfig.maxRealisticSpeedKmh,
        trackingIntervalMs: LocationConfig.trackingIntervalMs,
        getCurrentTimeoutSeconds: LocationConfig.getCurrentTimeout.inSeconds,
        emlidStaleSeconds: LocationConfig.emlidStaleSeconds,
        maxLastKnownAgeSeconds: LocationConfig.maxLastKnownAgeSeconds,
        coordinateDecimals: LocationConfig.coordinateDecimals,
        outlierAccuracyK: LocationConfig.outlierAccuracyK,
        stationaryAccuracyFactor: LocationConfig.stationaryAccuracyFactor,
        warmupRequireGoodFix: LocationConfig.warmupRequireGoodFix,
        kalmanQMetersPerSecond: LocationConfig.kalmanQMetersPerSecond,
      );

  GpsSettings copyWith({
    double? maxAccuracyMeters,
    double? goodFixThresholdMeters,
    bool? acceptAllUntilGoodFix,
    int? poorAccuracyDropsBeforeRelax,
    double? relaxedAccuracyMultiplier,
    double? distanceFilterMeters,
    double? staticNoiseThresholdMeters,
    int? staticNoiseWindowSeconds,
    double? maxRealisticSpeedKmh,
    int? trackingIntervalMs,
    int? getCurrentTimeoutSeconds,
    int? emlidStaleSeconds,
    int? maxLastKnownAgeSeconds,
    int? coordinateDecimals,
    double? outlierAccuracyK,
    double? stationaryAccuracyFactor,
    bool? warmupRequireGoodFix,
    double? kalmanQMetersPerSecond,
  }) =>
      GpsSettings(
        maxAccuracyMeters: maxAccuracyMeters ?? this.maxAccuracyMeters,
        goodFixThresholdMeters:
            goodFixThresholdMeters ?? this.goodFixThresholdMeters,
        acceptAllUntilGoodFix:
            acceptAllUntilGoodFix ?? this.acceptAllUntilGoodFix,
        poorAccuracyDropsBeforeRelax:
            poorAccuracyDropsBeforeRelax ?? this.poorAccuracyDropsBeforeRelax,
        relaxedAccuracyMultiplier:
            relaxedAccuracyMultiplier ?? this.relaxedAccuracyMultiplier,
        distanceFilterMeters: distanceFilterMeters ?? this.distanceFilterMeters,
        staticNoiseThresholdMeters:
            staticNoiseThresholdMeters ?? this.staticNoiseThresholdMeters,
        staticNoiseWindowSeconds:
            staticNoiseWindowSeconds ?? this.staticNoiseWindowSeconds,
        maxRealisticSpeedKmh:
            maxRealisticSpeedKmh ?? this.maxRealisticSpeedKmh,
        trackingIntervalMs: trackingIntervalMs ?? this.trackingIntervalMs,
        getCurrentTimeoutSeconds:
            getCurrentTimeoutSeconds ?? this.getCurrentTimeoutSeconds,
        emlidStaleSeconds: emlidStaleSeconds ?? this.emlidStaleSeconds,
        maxLastKnownAgeSeconds:
            maxLastKnownAgeSeconds ?? this.maxLastKnownAgeSeconds,
        coordinateDecimals: coordinateDecimals ?? this.coordinateDecimals,
        outlierAccuracyK: outlierAccuracyK ?? this.outlierAccuracyK,
        stationaryAccuracyFactor:
            stationaryAccuracyFactor ?? this.stationaryAccuracyFactor,
        warmupRequireGoodFix:
            warmupRequireGoodFix ?? this.warmupRequireGoodFix,
        kalmanQMetersPerSecond:
            kalmanQMetersPerSecond ?? this.kalmanQMetersPerSecond,
      );

  Map<String, dynamic> toJson() => {
        'maxAccuracyMeters': maxAccuracyMeters,
        'goodFixThresholdMeters': goodFixThresholdMeters,
        'acceptAllUntilGoodFix': acceptAllUntilGoodFix,
        'poorAccuracyDropsBeforeRelax': poorAccuracyDropsBeforeRelax,
        'relaxedAccuracyMultiplier': relaxedAccuracyMultiplier,
        'distanceFilterMeters': distanceFilterMeters,
        'staticNoiseThresholdMeters': staticNoiseThresholdMeters,
        'staticNoiseWindowSeconds': staticNoiseWindowSeconds,
        'maxRealisticSpeedKmh': maxRealisticSpeedKmh,
        'trackingIntervalMs': trackingIntervalMs,
        'getCurrentTimeoutSeconds': getCurrentTimeoutSeconds,
        'emlidStaleSeconds': emlidStaleSeconds,
        'maxLastKnownAgeSeconds': maxLastKnownAgeSeconds,
        'coordinateDecimals': coordinateDecimals,
        'outlierAccuracyK': outlierAccuracyK,
        'stationaryAccuracyFactor': stationaryAccuracyFactor,
        'warmupRequireGoodFix': warmupRequireGoodFix,
        'kalmanQMetersPerSecond': kalmanQMetersPerSecond,
      };

  /// Baca dari JSON; field yang hilang memakai default, semua nilai di-clamp
  /// ke rentang valid supaya setelan rusak tak bisa membuat tracking gagal.
  factory GpsSettings.fromJson(Map<String, dynamic> j) {
    final d = GpsSettings.defaults();
    double dbl(String k, double fb) => (j[k] as num?)?.toDouble() ?? fb;
    int integer(String k, int fb) => (j[k] as num?)?.toInt() ?? fb;
    return GpsSettings(
      maxAccuracyMeters: _clampD(
          dbl('maxAccuracyMeters', d.maxAccuracyMeters),
          maxAccuracyMin, maxAccuracyMax),
      goodFixThresholdMeters: _clampD(
          dbl('goodFixThresholdMeters', d.goodFixThresholdMeters),
          goodFixMin, goodFixMax),
      acceptAllUntilGoodFix:
          (j['acceptAllUntilGoodFix'] as bool?) ?? d.acceptAllUntilGoodFix,
      poorAccuracyDropsBeforeRelax: _clampI(
          integer('poorAccuracyDropsBeforeRelax',
              d.poorAccuracyDropsBeforeRelax),
          poorDropsMin, poorDropsMax),
      relaxedAccuracyMultiplier: _clampD(
          dbl('relaxedAccuracyMultiplier', d.relaxedAccuracyMultiplier),
          relaxedMultMin, relaxedMultMax),
      distanceFilterMeters: _clampD(
          dbl('distanceFilterMeters', d.distanceFilterMeters),
          distanceFilterMin, distanceFilterMax),
      staticNoiseThresholdMeters: _clampD(
          dbl('staticNoiseThresholdMeters', d.staticNoiseThresholdMeters),
          staticNoiseMin, staticNoiseMax),
      staticNoiseWindowSeconds: _clampI(
          integer('staticNoiseWindowSeconds', d.staticNoiseWindowSeconds),
          staticWindowMin, staticWindowMax),
      maxRealisticSpeedKmh: _clampD(
          dbl('maxRealisticSpeedKmh', d.maxRealisticSpeedKmh),
          maxSpeedMin, maxSpeedMax),
      trackingIntervalMs: _clampI(
          integer('trackingIntervalMs', d.trackingIntervalMs),
          trackingIntervalMin, trackingIntervalMax),
      getCurrentTimeoutSeconds: _clampI(
          integer('getCurrentTimeoutSeconds', d.getCurrentTimeoutSeconds),
          getCurrentTimeoutMin, getCurrentTimeoutMax),
      emlidStaleSeconds: _clampI(
          integer('emlidStaleSeconds', d.emlidStaleSeconds),
          emlidStaleMin, emlidStaleMax),
      maxLastKnownAgeSeconds: _clampI(
          integer('maxLastKnownAgeSeconds', d.maxLastKnownAgeSeconds),
          lastKnownAgeMin, lastKnownAgeMax),
      coordinateDecimals: _clampI(
          integer('coordinateDecimals', d.coordinateDecimals),
          coordinateDecimalsMin, coordinateDecimalsMax),
      outlierAccuracyK: _clampD(
          dbl('outlierAccuracyK', d.outlierAccuracyK), outlierKMin, outlierKMax),
      stationaryAccuracyFactor: _clampD(
          dbl('stationaryAccuracyFactor', d.stationaryAccuracyFactor),
          stationaryFactorMin, stationaryFactorMax),
      warmupRequireGoodFix:
          (j['warmupRequireGoodFix'] as bool?) ?? d.warmupRequireGoodFix,
      kalmanQMetersPerSecond: _clampD(
          dbl('kalmanQMetersPerSecond', d.kalmanQMetersPerSecond),
          kalmanQMin, kalmanQMax),
    );
  }

  /// Adapter ke [GpsFilterConfig] yang dipakai [GpsFilterPipeline].
  GpsFilterConfig toFilterConfig() => GpsFilterConfig(
        maxAccuracyMeters: maxAccuracyMeters,
        goodFixThresholdMeters: goodFixThresholdMeters,
        acceptAllUntilGoodFix: acceptAllUntilGoodFix,
        poorAccuracyDropsBeforeRelax: poorAccuracyDropsBeforeRelax,
        relaxedAccuracyMultiplier: relaxedAccuracyMultiplier,
        maxRealisticSpeedKmh: maxRealisticSpeedKmh,
        staticNoiseThresholdMeters: staticNoiseThresholdMeters,
        staticNoiseWindowMs: staticNoiseWindowSeconds * 1000,
        coordinateRoundFactor: pow(10, coordinateDecimals).toDouble(),
        outlierAccuracyK: outlierAccuracyK,
        stationaryAccuracyFactor: stationaryAccuracyFactor,
        warmupRequireGoodFix: warmupRequireGoodFix,
        kalmanQMetersPerSecond: kalmanQMetersPerSecond,
        // Internal (bukan setelan user) — dari default terpusat.
        stationarySpeedThresholdMps:
            LocationConfig.stationarySpeedThresholdMps,
        kalmanReportedAccuracyFloorFactor:
            LocationConfig.kalmanReportedAccuracyFloorFactor,
      );

  static double _clampD(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);
  static int _clampI(int v, int min, int max) =>
      v < min ? min : (v > max ? max : v);
}
