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
  static const double emaAlphaMin = 0.1, emaAlphaMax = 1.0;
  static const double emaBypassMin = 5, emaBypassMax = 120;
  static const double distanceFilterMin = 0, distanceFilterMax = 50;
  static const double staticNoiseMin = 0, staticNoiseMax = 10;
  static const int staticWindowMin = 0, staticWindowMax = 3600;
  static const double maxSpeedMin = 30, maxSpeedMax = 400;
  static const int trackingIntervalMin = 200, trackingIntervalMax = 10000;
  static const int getCurrentTimeoutMin = 3, getCurrentTimeoutMax = 60;
  static const int emlidStaleMin = 2, emlidStaleMax = 60;
  static const int lastKnownAgeMin = 5, lastKnownAgeMax = 600;
  static const int coordinateDecimalsMin = 4, coordinateDecimalsMax = 8;

  // ─── Field ───────────────────────────────────────────────────────────────
  final double maxAccuracyMeters;
  final double goodFixThresholdMeters;
  final bool acceptAllUntilGoodFix;
  final int poorAccuracyDropsBeforeRelax;
  final double relaxedAccuracyMultiplier;
  final double emaAlpha;
  final double emaBypassSpeedKmh;
  final double distanceFilterMeters;
  final double staticNoiseThresholdMeters;
  final int staticNoiseWindowSeconds;
  final double maxRealisticSpeedKmh;
  final int trackingIntervalMs;
  final int getCurrentTimeoutSeconds;
  final int emlidStaleSeconds;
  final int maxLastKnownAgeSeconds;
  final int coordinateDecimals;

  const GpsSettings({
    required this.maxAccuracyMeters,
    required this.goodFixThresholdMeters,
    required this.acceptAllUntilGoodFix,
    required this.poorAccuracyDropsBeforeRelax,
    required this.relaxedAccuracyMultiplier,
    required this.emaAlpha,
    required this.emaBypassSpeedKmh,
    required this.distanceFilterMeters,
    required this.staticNoiseThresholdMeters,
    required this.staticNoiseWindowSeconds,
    required this.maxRealisticSpeedKmh,
    required this.trackingIntervalMs,
    required this.getCurrentTimeoutSeconds,
    required this.emlidStaleSeconds,
    required this.maxLastKnownAgeSeconds,
    required this.coordinateDecimals,
  });

  /// Default dari konstanta terpusat [LocationConfig].
  factory GpsSettings.defaults() => GpsSettings(
        maxAccuracyMeters: LocationConfig.maxAccuracyMeters,
        goodFixThresholdMeters: LocationConfig.goodFixThresholdMeters,
        acceptAllUntilGoodFix: LocationConfig.acceptAllUntilGoodFix,
        poorAccuracyDropsBeforeRelax:
            LocationConfig.poorAccuracyDropsBeforeRelax,
        relaxedAccuracyMultiplier: LocationConfig.relaxedAccuracyMultiplier,
        emaAlpha: LocationConfig.emaAlpha,
        emaBypassSpeedKmh: LocationConfig.emaBypassSpeedKmh,
        distanceFilterMeters: LocationConfig.distanceFilterMeters,
        staticNoiseThresholdMeters: LocationConfig.staticNoiseThresholdMeters,
        staticNoiseWindowSeconds: LocationConfig.staticNoiseWindowMs ~/ 1000,
        maxRealisticSpeedKmh: LocationConfig.maxRealisticSpeedKmh,
        trackingIntervalMs: LocationConfig.trackingIntervalMs,
        getCurrentTimeoutSeconds: LocationConfig.getCurrentTimeout.inSeconds,
        emlidStaleSeconds: LocationConfig.emlidStaleSeconds,
        maxLastKnownAgeSeconds: LocationConfig.maxLastKnownAgeSeconds,
        coordinateDecimals: LocationConfig.coordinateDecimals,
      );

  GpsSettings copyWith({
    double? maxAccuracyMeters,
    double? goodFixThresholdMeters,
    bool? acceptAllUntilGoodFix,
    int? poorAccuracyDropsBeforeRelax,
    double? relaxedAccuracyMultiplier,
    double? emaAlpha,
    double? emaBypassSpeedKmh,
    double? distanceFilterMeters,
    double? staticNoiseThresholdMeters,
    int? staticNoiseWindowSeconds,
    double? maxRealisticSpeedKmh,
    int? trackingIntervalMs,
    int? getCurrentTimeoutSeconds,
    int? emlidStaleSeconds,
    int? maxLastKnownAgeSeconds,
    int? coordinateDecimals,
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
        emaAlpha: emaAlpha ?? this.emaAlpha,
        emaBypassSpeedKmh: emaBypassSpeedKmh ?? this.emaBypassSpeedKmh,
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
      );

  Map<String, dynamic> toJson() => {
        'maxAccuracyMeters': maxAccuracyMeters,
        'goodFixThresholdMeters': goodFixThresholdMeters,
        'acceptAllUntilGoodFix': acceptAllUntilGoodFix,
        'poorAccuracyDropsBeforeRelax': poorAccuracyDropsBeforeRelax,
        'relaxedAccuracyMultiplier': relaxedAccuracyMultiplier,
        'emaAlpha': emaAlpha,
        'emaBypassSpeedKmh': emaBypassSpeedKmh,
        'distanceFilterMeters': distanceFilterMeters,
        'staticNoiseThresholdMeters': staticNoiseThresholdMeters,
        'staticNoiseWindowSeconds': staticNoiseWindowSeconds,
        'maxRealisticSpeedKmh': maxRealisticSpeedKmh,
        'trackingIntervalMs': trackingIntervalMs,
        'getCurrentTimeoutSeconds': getCurrentTimeoutSeconds,
        'emlidStaleSeconds': emlidStaleSeconds,
        'maxLastKnownAgeSeconds': maxLastKnownAgeSeconds,
        'coordinateDecimals': coordinateDecimals,
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
      emaAlpha: _clampD(dbl('emaAlpha', d.emaAlpha), emaAlphaMin, emaAlphaMax),
      emaBypassSpeedKmh: _clampD(
          dbl('emaBypassSpeedKmh', d.emaBypassSpeedKmh),
          emaBypassMin, emaBypassMax),
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
        emaAlpha: emaAlpha,
        emaBypassSpeedKmh: emaBypassSpeedKmh,
        coordinateRoundFactor: pow(10, coordinateDecimals).toDouble(),
        // Parameter baru — sementara ambil dari default terpusat; dijadikan
        // tunable di GpsSettings pada tahap lanjut.
        outlierAccuracyK: LocationConfig.outlierAccuracyK,
        stationaryAccuracyFactor: LocationConfig.stationaryAccuracyFactor,
        warmupRequireGoodFix: LocationConfig.warmupRequireGoodFix,
        kalmanQMetersPerSecond: LocationConfig.kalmanQMetersPerSecond,
      );

  static double _clampD(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);
  static int _clampI(int v, int min, int max) =>
      v < min ? min : (v > max ? max : v);
}
