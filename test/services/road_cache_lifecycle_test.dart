import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_service.dart';

/// basemapId cache road-tile harus konsisten dengan penyimpanan .pbf:
/// cloud per-company (`roads_<id>`, sejajar `roads_<id>.pbf`), lokal `roads_local`.
/// Dipakai saat clear cache (delete → hapus; update/ganti → clear lalu regenerate).
void main() {
  test('roadBasemapId: cloud pakai companyId', () {
    expect(RoutingService.roadBasemapId(7), 'roads_7');
    expect(RoutingService.roadBasemapId(123), 'roads_123');
  });

  test('roadBasemapId: lokal (tanpa company) → roads_local', () {
    expect(RoutingService.roadBasemapId(null), 'roads_local');
  });
}
