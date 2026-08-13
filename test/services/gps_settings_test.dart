import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/settings/gps_settings.dart';
import 'package:geoform_app/config/location_config.dart';
import 'package:geoform_app/services/gps/gps_filter_pipeline.dart';

void main() {
  group('GpsSettings', () {
    test('defaults sesuai LocationConfig', () {
      final d = GpsSettings.defaults();
      expect(d.maxAccuracyMeters, LocationConfig.maxAccuracyMeters);
      expect(d.emaAlpha, LocationConfig.emaAlpha);
      expect(d.maxLastKnownAgeSeconds, LocationConfig.maxLastKnownAgeSeconds);
    });

    test('toJson → fromJson round-trip', () {
      final s = GpsSettings.defaults().copyWith(
        maxAccuracyMeters: 42,
        emaAlpha: 0.8,
        staticNoiseWindowSeconds: 30,
      );
      final back = GpsSettings.fromJson(s.toJson());
      expect(back.maxAccuracyMeters, 42);
      expect(back.emaAlpha, 0.8);
      expect(back.staticNoiseWindowSeconds, 30);
    });

    test('fromJson meng-clamp nilai di luar rentang', () {
      final s = GpsSettings.fromJson({
        'maxAccuracyMeters': 99999, // > max
        'emaAlpha': 0, // < min
        'coordinateDecimals': 99, // > max
      });
      expect(s.maxAccuracyMeters,
          lessThanOrEqualTo(GpsSettings.maxAccuracyMax));
      expect(s.emaAlpha, greaterThanOrEqualTo(GpsSettings.emaAlphaMin));
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

    test('setelan mengalir ke pipeline: maxAccuracy kustom menyaring', () {
      final s = GpsSettings.defaults().copyWith(maxAccuracyMeters: 15);
      final p = GpsFilterPipeline(s.toFilterConfig());
      final t0 = DateTime(2026, 8, 13, 12, 0, 0);
      p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
      // 18m > maxAccuracy(15) setelah fix bagus → dibuang sesuai setelan user
      final out = p.process(
        latitude: 0.01, longitude: 0, accuracy: 18,
        speed: 0, timestamp: t0.add(const Duration(seconds: 1)));
      expect(out, isNull);
    });
  });
}
