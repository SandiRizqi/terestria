import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../widgets/map/tools/map_tools_controller.dart';
import '../widgets/map/tools/map_tools_layers.dart';
import '../widgets/map/tools/map_tools_panel.dart';

/// Mixin penyambung alat ukur peta bersama ke sebuah State layar peta.
/// Integrasi cukup 3 kait:
///  1. `onTap: (pos, latlng) { if (handleMapToolsTap(latlng)) return; <lama>; }`
///  2. tambahkan `...buildMapToolsLayers()` ke `children` FlutterMap
///  3. taruh `buildMapToolsPanel()` di Stack (mis. Positioned kanan-bawah)
///
/// Controller dimiliki mixin & otomatis di-dispose. Saat tak ada tool aktif,
/// [handleMapToolsTap] mengembalikan false → perilaku tap lama tak berubah.
mixin MapToolsHost<T extends StatefulWidget> on State<T> {
  final MapToolsController mapToolsController = MapToolsController();

  @override
  void dispose() {
    mapToolsController.dispose();
    super.dispose();
  }

  /// Panggil PERTAMA dari `MapOptions.onTap`. True bila tap dikonsumsi tool.
  bool handleMapToolsTap(LatLng latlng) {
    if (!mapToolsController.isActive) return false;
    mapToolsController.addPoint(latlng);
    return true;
  }

  /// Layer alat ukur untuk disisipkan ke `children` FlutterMap.
  List<Widget> buildMapToolsLayers() =>
      [MapToolsLayer(controller: mapToolsController)];

  /// Panel/FAB alat ukur untuk ditaruh di Stack layar.
  Widget buildMapToolsPanel() => MapToolsPanel(
        controller: mapToolsController,
        onFocusPoint: focusMapToolsPoint,
      );

  /// Peta milik layar, untuk menggeser kamera ke titik yang diketik/diedit di
  /// alat ukur. Override di layar peta; null = tidak digeser.
  MapController? get mapToolsMapController => null;

  /// Geser peta ke [p] (zoom minimal 16, tidak memperkecil zoom sekarang).
  /// Peta yang belum dirender diabaikan.
  void focusMapToolsPoint(LatLng p) {
    final map = mapToolsMapController;
    if (map == null) return;
    try {
      map.move(p, math.max(map.camera.zoom, 16));
    } catch (_) {
      // Kamera belum siap (peta belum dirender) — tidak ada yang digeser.
    }
  }
}
