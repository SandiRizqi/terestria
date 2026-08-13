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

  test('anti-beku: setelah fix bagus lalu sinyal memburuk, marker tetap emit', () {
    final p = GpsFilterPipeline(cfg());
    // fix bagus dulu → filter akurasi aktif
    expect(
      p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0),
      isNotNull,
    );
    // sinyal memburuk (di atas maxAccuracy) — beberapa reading awal dibuang…
    var lastOut;
    for (var i = 1; i <= 6; i++) {
      lastOut = p.process(
        latitude: 0.01 * i, longitude: 0, accuracy: 70,
        speed: 0, timestamp: t0.add(Duration(seconds: i)));
    }
    // …tapi setelah beberapa drop beruntun, pipeline melonggar & emit lagi
    // (marker tidak boleh beku permanen di area sinyal lemah).
    expect(lastOut, isNotNull);
  });

  test('good fix baru meng-arm ulang filter akurasi setelah longgar', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    for (var i = 1; i <= 5; i++) {
      p.process(latitude: 0.01 * i, longitude: 0, accuracy: 70,
        speed: 0, timestamp: t0.add(Duration(seconds: i)));
    }
    // good fix lagi
    p.process(latitude: 1, longitude: 1, accuracy: 8,
      speed: 0, timestamp: t0.add(const Duration(seconds: 6)));
    // sekarang filter aktif lagi → reading buruk berikutnya dibuang
    final out = p.process(latitude: 1.5, longitude: 1, accuracy: 70,
      speed: 0, timestamp: t0.add(const Duration(seconds: 7)));
    expect(out, isNull);
  });

  test('akurasi laporan mencerminkan pergeseran EMA (bukan sekadar raw)', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    final out = p.process(
      latitude: 0.001, longitude: 0, accuracy: 10, // raw 10m, tapi EMA menggeser ~44m
      speed: 0, timestamp: t0.add(const Duration(seconds: 1)));
    expect(out, isNotNull);
    // titik ter-EMA ~44m dari raw → akurasi dilaporkan tak boleh tetap 10m
    expect(out!.accuracy, greaterThan(30));
  });

  test('speed OS tak diketahui: spike diturunkan dari jarak/waktu', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    // lompat ~111 km dalam 1 detik dengan speed=-1 → derived >> 180 km/h → dibuang
    final out = p.process(
      latitude: 1.0, longitude: 0, accuracy: 10,
      speed: -1, timestamp: t0.add(const Duration(seconds: 1)));
    expect(out, isNull);
  });

  test('speed=-1 tanpa gerak berlebihan tetap diterima (tak salah drop)', () {
    final p = GpsFilterPipeline(cfg());
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    final out = p.process(
      latitude: 0.001, longitude: 0, accuracy: 10, // ~111 m dalam 1s ≈ 400 km/h? tidak
      speed: -1, timestamp: t0.add(const Duration(seconds: 30))); // 111m/30s ≈ 13 km/h
    expect(out, isNotNull);
  });

  test('mode longgar tetap membuang fix sampah di atas cap (relaxedMultiplier)', () {
    final p = GpsFilterPipeline(cfg()); // default mult 3, maxAcc 50 → cap 150
    p.process(latitude: 0, longitude: 0, accuracy: 10, speed: 0, timestamp: t0);
    // buat memburuk → melonggar
    for (var i = 1; i <= 4; i++) {
      p.process(latitude: 0.01 * i, longitude: 0, accuracy: 70,
        speed: 0, timestamp: t0.add(Duration(seconds: i)));
    }
    // sampah 500m (> cap 150) tetap dibuang meski sedang longgar
    final garbage = p.process(latitude: 0.2, longitude: 0, accuracy: 500,
      speed: 0, timestamp: t0.add(const Duration(seconds: 10)));
    expect(garbage, isNull);
    // 70m (<= cap) masih diterima → marker tetap bergerak
    final ok = p.process(latitude: 0.25, longitude: 0, accuracy: 70,
      speed: 0, timestamp: t0.add(const Duration(seconds: 11)));
    expect(ok, isNotNull);
  });

  test('sebelum fix bagus pertama, cap tak berlaku (acceptAllUntilGoodFix)', () {
    final p = GpsFilterPipeline(cfg());
    // belum pernah good fix → 500m pun diterima agar marker muncul
    final out = p.process(latitude: 0, longitude: 0, accuracy: 500,
      speed: 0, timestamp: t0);
    expect(out, isNotNull);
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
