import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/gps/gps_filter_pipeline.dart';

/// Pipeline baru: SELALU keluarkan titik display (marker mengikuti cepat);
/// [GeoPoint.recordable] menandai apakah titik layak DIREKAM ke jalur.
void main() {
  final t0 = DateTime(2026, 8, 13, 12, 0, 0);
  GpsFilterConfig cfg() => GpsFilterConfig.fromDefaults();
  DateTime at(int sec) => t0.add(Duration(seconds: sec));

  test('display selalu keluar walau akurasi buruk (marker cepat muncul)', () {
    final p = GpsFilterPipeline(cfg());
    final out = p.process(
        latitude: 1, longitude: 2, accuracy: 80, speed: 0, timestamp: t0);
    expect(out, isNotNull, reason: 'marker harus tampil');
    expect(out!.recordable, isFalse, reason: 'belum ada fix bagus (warm-up)');
  });

  test('warm-up: sebelum fix bagus pertama, tidak recordable', () {
    final p = GpsFilterPipeline(cfg());
    // 30 m > goodFixThreshold (20) → belum good fix
    final out = p.process(
        latitude: 0, longitude: 0, accuracy: 30, speed: 0, timestamp: t0);
    expect(out!.recordable, isFalse);
  });

  test('setelah fix bagus pertama, gerak normal → recordable', () {
    final p = GpsFilterPipeline(cfg());
    // fix bagus (acc 5 <= 20) & titik pertama (tanpa prev) → recordable
    final first = p.process(
        latitude: 0, longitude: 0, accuracy: 5, speed: 0, timestamp: t0);
    expect(first!.recordable, isTrue);
    // ~11 m dalam 1 s → bukan diam, bukan outlier
    final out = p.process(
        latitude: 0.0001, longitude: 0, accuracy: 5, speed: 1, timestamp: at(1));
    expect(out!.recordable, isTrue);
  });

  test('OUTLIER/teleport ditolak walau speed OS = 0 (bug utama loncat)', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 5, speed: 0, timestamp: t0);
    // ~111 m dalam 1 s, tapi OS speed = 0 → dulu lolos, sekarang ditolak-record
    final out = p.process(
        latitude: 0.001, longitude: 0, accuracy: 5, speed: 0, timestamp: at(1));
    expect(out, isNotNull, reason: 'marker tetap tampil');
    expect(out!.recordable, isFalse, reason: 'teleport tak boleh direkam');
  });

  test('drift diam ditahan dari rekaman (hold)', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 5, speed: 0, timestamp: t0);
    // ~2.2 m < radius diam (max(0.5, 1×acc)=5) → ditahan
    final out = p.process(
        latitude: 0.00002, longitude: 0, accuracy: 5, speed: 0, timestamp: at(1));
    expect(out!.recordable, isFalse);
  });

  test('Kalman meratakan reading (tak meloncat penuh ke raw)', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 5, speed: 0, timestamp: t0);
    // var: 25 → predict +1×3² = 34 → K = 34/(34+25) = 0.5763
    // kLat = 0.5763 × 0.001 = 0.000576
    final out = p.process(
        latitude: 0.001, longitude: 0, accuracy: 5, speed: 0, timestamp: at(1));
    expect(out!.latitude, closeTo(0.000576, 5e-6));
    expect(out.latitude, lessThan(0.001)); // tergeser dari raw = smoothing
  });

  test('reset() mengosongkan state (warm-up & Kalman ulang)', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 5, speed: 0, timestamp: t0);
    p.reset();
    final out = p.process(
        latitude: 9, longitude: 9, accuracy: 80, speed: 0, timestamp: t0);
    expect(out, isNotNull);
    expect(out!.recordable, isFalse, reason: 'good fix hilang → warm-up lagi');
    expect(out.latitude, closeTo(9, 1e-6), reason: 'Kalman re-init di titik baru');
  });

  test('speed OS diketahui tetap dipakai untuk field speed', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 5, speed: 0, timestamp: t0);
    final out = p.process(
        latitude: 0.0001, longitude: 0, accuracy: 5, speed: 2, timestamp: at(1));
    expect(out!.speed, closeTo(7.2, 0.05)); // 2 m/s = 7.2 km/h
  });
}
