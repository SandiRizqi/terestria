import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/gps/gps_filter_pipeline.dart';

void main() {
  final t0 = DateTime(2026, 8, 13, 12, 0, 0);
  GpsFilterConfig cfg() => GpsFilterConfig.fromDefaults();

  test('reading pertama dengan akurasi buruk tetap diterima (acceptAllUntilGoodFix)', () {
    final p = GpsFilterPipeline(cfg());
    final out = p.process(
      latitude: 1.0, longitude: 2.0, accuracy: 80, speed: 0, timestamp: t0);
    expect(out, isNotNull);
  });

  test('setelah fix bagus, akurasi > maxAccuracy dibuang', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    final out = p.process(
      latitude: 0.01, longitude: 0, accuracy: 60,
      speed: 0, timestamp: t0.add(const Duration(seconds: 1)));
    expect(out, isNull);
  });

  test('speed spike tidak wajar dibuang', () {
    final p = GpsFilterPipeline(cfg());
    final out = p.process(
      latitude: 0, longitude: 0, accuracy: 10, speed: 60, timestamp: t0); // 216 km/h
    expect(out, isNull);
  });

  test('static-noise: gerak < threshold setelah fix bagus dibuang', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    final out = p.process(
      latitude: 0.000001, longitude: 0, accuracy: 10, // ~0.11 m
      speed: 0, timestamp: t0.add(const Duration(seconds: 1)));
    expect(out, isNull);
  });

  test('EMA meratakan reading kedua (alpha 0.6)', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    final out = p.process(
      latitude: 0.001, longitude: 0, accuracy: 10, // ~111 m, lolos static
      speed: 0, timestamp: t0.add(const Duration(seconds: 1)));
    expect(out, isNotNull);
    // 0.6*0.001 + 0.4*0 = 0.0006
    expect(out!.latitude, closeTo(0.0006, 1e-9));
  });

  test('gerak cepat mem-bypass EMA (pakai koordinat mentah)', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    final out = p.process(
      latitude: 0.001, longitude: 0, accuracy: 10,
      speed: 15, timestamp: t0.add(const Duration(seconds: 1))); // 54 km/h > 30
    expect(out!.latitude, closeTo(0.001, 1e-9));
  });

  test('reset() menghapus state EMA & fix', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    p.reset();
    // Setelah reset, reading akurasi buruk diterima lagi (belum ada good fix).
    final out = p.process(
      latitude: 5, longitude: 5, accuracy: 90, speed: 0, timestamp: t0);
    expect(out, isNotNull);
  });
}
