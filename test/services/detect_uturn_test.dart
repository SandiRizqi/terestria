import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/services/routing_service.dart';

/// U-turn hanya benar bila ARAH GERAK berbalik ~180° (paruh awal vs paruh akhir
/// window), pelan, dan tak berpindah jauh. Bukan sekadar pelan + dekat.
void main() {
  final svc = RoutingService();

  List<TrackPoint> pts(List<LatLng> ll, double speedKmh) =>
      [for (final p in ll) TrackPoint(p, speedKmh)];

  test('jalan LURUS pelan → BUKAN U-turn', () {
    // 14 titik ke utara, langkah ~2 m (span < 50 m), pelan 2 km/j.
    final ll = [for (var i = 0; i < 14; i++) LatLng(1.0 + i * 0.00002, 100.0)];
    expect(svc.detectUTurn(pts(ll, 2.0)), isFalse);
  });

  test('benar-benar BERBALIK pelan → U-turn', () {
    // 7 titik ke utara lalu 7 titik balik ke selatan (kembali dekat awal).
    final ll = <LatLng>[];
    for (var i = 0; i < 7; i++) ll.add(LatLng(1.0 + i * 0.00002, 100.0));
    for (var i = 6; i >= 0; i--) ll.add(LatLng(1.0 + i * 0.00002, 100.0));
    expect(svc.detectUTurn(pts(ll, 2.0)), isTrue);
  });

  test('berbalik tapi CEPAT (>5 km/j) → tidak dianggap U-turn', () {
    final ll = <LatLng>[];
    for (var i = 0; i < 7; i++) ll.add(LatLng(1.0 + i * 0.00002, 100.0));
    for (var i = 6; i >= 0; i--) ll.add(LatLng(1.0 + i * 0.00002, 100.0));
    expect(svc.detectUTurn(pts(ll, 12.0)), isFalse);
  });

  test('window terlalu pendek → false', () {
    final ll = [for (var i = 0; i < 5; i++) LatLng(1.0 + i * 0.00002, 100.0)];
    expect(svc.detectUTurn(pts(ll, 2.0)), isFalse);
  });
}
