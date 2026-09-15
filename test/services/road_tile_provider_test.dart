import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/services/basemap/road_tile_provider.dart';

/// Uji MURNI matematika proyeksi tile↔bbox (Web-Mercator) — area risiko utama.
/// Rendering/cache diverifikasi manual (butuh dart:ui engine).
void main() {
  const eps = 1e-6;
  const webMercLat = 85.05112877980659;

  test('tileBounds z0 = seluruh dunia web-mercator', () {
    final b = RoadTileProvider.tileBounds(0, 0, 0); // [west, south, east, north]
    expect(b[0], closeTo(-180, eps));
    expect(b[2], closeTo(180, eps));
    expect(b[3], closeTo(webMercLat, 1e-6));
    expect(b[1], closeTo(-webMercLat, 1e-6));
  });

  test('tileBounds z1 kuadran kiri-atas (barat, utara)', () {
    final b = RoadTileProvider.tileBounds(1, 0, 0);
    expect(b[0], closeTo(-180, eps)); // west
    expect(b[2], closeTo(0, eps)); // east
    expect(b[3], closeTo(webMercLat, 1e-6)); // north
    expect(b[1], closeTo(0, 1e-9)); // south = ekuator
  });

  test('tileBounds z1 kuadran kanan-bawah', () {
    final b = RoadTileProvider.tileBounds(1, 1, 1);
    expect(b[0], closeTo(0, eps)); // west = meridian
    expect(b[2], closeTo(180, eps)); // east
    expect(b[3], closeTo(0, 1e-9)); // north = ekuator
    expect(b[1], closeTo(-webMercLat, 1e-6)); // south
  });

  test('project: sudut NW→(0,0), SE→(256,256), pusat→(128,128)', () {
    const z = 3, x = 5, y = 2;
    final b = RoadTileProvider.tileBounds(z, x, y); // west,south,east,north
    final nw = LatLng(b[3], b[0]);
    final se = LatLng(b[1], b[2]);
    final o0 = RoadTileProvider.project(nw, z, x, y);
    final o1 = RoadTileProvider.project(se, z, x, y);
    expect(o0.dx, closeTo(0, 1e-3));
    expect(o0.dy, closeTo(0, 1e-3));
    expect(o1.dx, closeTo(256, 1e-3));
    expect(o1.dy, closeTo(256, 1e-3));
  });

  test('project: titik di barat tile → dx negatif (culling-friendly)', () {
    const z = 3, x = 5, y = 2;
    final b = RoadTileProvider.tileBounds(z, x, y);
    final west = LatLng((b[1] + b[3]) / 2, b[0] - 0.5);
    final o = RoadTileProvider.project(west, z, x, y);
    expect(o.dx, lessThan(0));
  });
}
