import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/basemap/road_tile_provider.dart';

/// Zoom minimum default: layer jalan tampil hanya saat **zoom > 10**
/// (jaringan penuh di zoom jauh terlalu padat & berat).
const double kRoadLayerMinZoom = 10.0;

/// Keputusan murni apakah layer jalan digambar: butuh toggle ON, ada data, dan
/// zoom di atas [minZoom]. Dipisah agar mudah diuji tanpa memompa FlutterMap.
bool roadLayerVisible({
  required bool visible,
  required bool hasData,
  required double zoom,
  double minZoom = kRoadLayerMinZoom,
}) =>
    visible && hasData && zoom > minZoom;

/// Layer basemap jaringan jalan (raster on-device, lazy + cache SQLite).
///
/// Dipakai sebagai child [FlutterMap] di atas basemap, di bawah GeoJSON/route.
/// Menggambar `TileLayer` ber-[RoadTileProvider] HANYA saat [roadLayerVisible]
/// terpenuhi; selain itu mengembalikan widget kosong (nol beban).
class RoadNetworkLayer extends StatelessWidget {
  /// Provider tile jalan untuk data aktif; `null` = belum ada data jalan.
  final RoadTileProvider? provider;

  /// Status toggle layer (user bisa mematikan).
  final bool visible;

  /// Zoom minimum (tampil saat zoom > nilai ini).
  final double minZoom;

  const RoadNetworkLayer({
    super.key,
    required this.provider,
    required this.visible,
    this.minZoom = kRoadLayerMinZoom,
  });

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final zoom = MapCamera.of(context).zoom;
    if (!roadLayerVisible(
        visible: visible, hasData: p != null, zoom: zoom, minZoom: minZoom)) {
      return const SizedBox.shrink();
    }
    return TileLayer(
      // URL diabaikan — RoadTileProvider merender sendiri; placeholder agar
      // TileLayer valid tanpa jaringan.
      urlTemplate: 'roads://{z}/{x}/{y}',
      tileProvider: p,
      tileSize: kRoadTileSize.toDouble(),
      // Data lokal — jangan coba naik ke tile induk lewat jaringan.
      maxNativeZoom: 22,
      minZoom: minZoom,
    );
  }
}
