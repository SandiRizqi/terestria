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

  group('companyIdForPath', () {
    final saved = const [
      DownloadedRoad(id: 3, name: 'PT A', path: '/docs/roads/roads_3.pbf'),
      DownloadedRoad(id: 8, name: 'PT B', path: '/docs/roads/roads_8.pbf'),
    ];

    test('path cocok cloud → companyId', () {
      expect(RoutingService.companyIdForPath('/docs/roads/roads_8.pbf', saved), 8);
    });

    test('path lokal (osm_routing) tak cocok → null', () {
      expect(
          RoutingService.companyIdForPath('/docs/osm_routing.pbf', saved), isNull);
    });

    test('path null → null', () {
      expect(RoutingService.companyIdForPath(null, saved), isNull);
    });
  });
}
