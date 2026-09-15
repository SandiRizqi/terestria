import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/settings/gps_settings.dart';
import 'package:geoform_app/config/location_config.dart';
import 'package:geoform_app/services/gps/gps_filter_pipeline.dart';

void main() {
  group('GpsSettings', () {
    test('defaults sesuai LocationConfig', () {
      final d = GpsSettings.defaults();
      expect(d.maxAccuracyMeters, LocationConfig.maxAccuracyMeters);
      expect(d.kalmanQMetersPerSecond, LocationConfig.kalmanQMetersPerSecond);
      expect(d.maxLastKnownAgeSeconds, LocationConfig.maxLastKnownAgeSeconds);
    });

    test('toJson → fromJson round-trip', () {
      final s = GpsSettings.defaults().copyWith(
        maxAccuracyMeters: 42,
        kalmanQMetersPerSecond: 8,
        staticNoiseWindowSeconds: 30,
      );
      final back = GpsSettings.fromJson(s.toJson());
      expect(back.maxAccuracyMeters, 42);
      expect(back.kalmanQMetersPerSecond, 8);
      expect(back.staticNoiseWindowSeconds, 30);
    });

    test('fromJson meng-clamp nilai di luar rentang', () {
      final s = GpsSettings.fromJson({
        'maxAccuracyMeters': 99999, // > max
        'kalmanQMetersPerSecond': 0, // < min
        'coordinateDecimals': 99, // > max
      });
      expect(s.maxAccuracyMeters,
          lessThanOrEqualTo(GpsSettings.maxAccuracyMax));
      expect(s.kalmanQMetersPerSecond, greaterThanOrEqualTo(GpsSettings.kalmanQMin));
      expect(s.coordinateDecimals,
          lessThanOrEqualTo(GpsSettings.coordinateDecimalsMax));
    });

    test('toFilterConfig menerjemahkan window detik → ms & decimals → factor', () {
      final s = GpsSettings.defaults()
          .copyWith(staticNoiseWindowSeconds: 5, coordinateDecimals: 6);
      final c = s.toFilterConfig();
      expect(c.staticNoiseWindowMs, 5000);
      expect(c.coordinateRoundFactor, 1000000.0);
    });

    test('param baru (Kalman/outlier/stationary/warmup) mengalir & di-clamp', () {
      final s = GpsSettings.defaults().copyWith(
        kalmanQMetersPerSecond: 5,
        outlierAccuracyK: 4,
        stationaryAccuracyFactor: 2,
        warmupRequireGoodFix: false,
      );
      final c = s.toFilterConfig();
      expect(c.kalmanQMetersPerSecond, 5);
      expect(c.outlierAccuracyK, 4);
      expect(c.stationaryAccuracyFactor, 2);
      expect(c.warmupRequireGoodFix, isFalse);
      // round-trip + clamp nilai liar
      final wild = GpsSettings.fromJson({
        'kalmanQMetersPerSecond': 9999,
        'outlierAccuracyK': -5,
      });
      expect(wild.kalmanQMetersPerSecond,
          lessThanOrEqualTo(GpsSettings.kalmanQMax));
      expect(wild.outlierAccuracyK,
          greaterThanOrEqualTo(GpsSettings.outlierKMin));
    });

    test('setelan mengalir ke pipeline: maxAccuracy kustom menyaring record', () {
      final s = GpsSettings.defaults().copyWith(maxAccuracyMeters: 15);
      final p = GpsFilterPipeline(s.toFilterConfig());
      final t0 = DateTime(2026, 8, 13, 12, 0, 0);
      p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
      // 18m > maxAccuracy(15) setelah fix bagus → marker tetap tampil, tapi
      // TIDAK direkam (recordable=false) sesuai setelan user.
      final out = p.process(
        latitude: 0.01, longitude: 0, accuracy: 18,
        speed: 0, timestamp: t0.add(const Duration(seconds: 1)));
      expect(out, isNotNull);
      expect(out!.recordable, isFalse);
    });
  });
}
