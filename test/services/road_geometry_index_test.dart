import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/services/basemap/road_geometry_index.dart';
import 'package:geoform_app/services/routing_dart/pbf_reader.dart';

/// Index geometri jalan dari OsmData: bangun polyline per way ber-`highway`
/// (kelas pejalan-kaki dilewati), dan query "way yang menyentuh bbox tile".
void main() {
  // Node grid kecil (semua lat 0, lon menaik) + satu node melenceng ke utara.
  final data = OsmData(
    const [
      OsmNode(1, 0.0, 0.00),
      OsmNode(2, 0.0, 0.01),
      OsmNode(3, 0.0, 0.02),
      OsmNode(4, 0.01, 0.02),
      OsmNode(5, 0.0, 0.03),
    ],
    const [
      OsmWay(10, [1, 2, 3], {'highway': 'residential'}), // digambar
      OsmWay(11, [3, 4], {'highway': 'footway'}), // dilewati (pejalan kaki)
      OsmWay(12, [3, 5], {'highway': 'track'}), // digambar (jalan kebun)
      OsmWay(13, [2], {'highway': 'residential'}), // <2 titik → dibuang
      OsmWay(14, [1, 999], {'highway': 'residential'}), // 1 node hilang → dibuang
      OsmWay(15, [1, 2], {}), // tanpa highway → dibuang
    ],
  );

  test('fromOsm: hanya way jalan yang valid (≥2 titik) yang masuk', () {
    final idx = RoadGeometryIndex.fromOsm(data);
    expect(idx.roads.length, 2); // residential + track
    final classes = idx.roads.map((r) => r.highway).toSet();
    expect(classes, {'residential', 'track'});
    for (final r in idx.roads) {
      expect(r.points.length, greaterThanOrEqualTo(2));
    }
  });

  test('fromOsm: refs → LatLng sesuai node', () {
    final idx = RoadGeometryIndex.fromOsm(data);
    final res = idx.roads.firstWhere((r) => r.highway == 'residential');
    expect(res.points.first, const LatLng(0.0, 0.00));
    expect(res.points.last, const LatLng(0.0, 0.02));
  });

  test('queryBounds: hanya kembalikan road yang bbox-nya beririsan', () {
    final idx = RoadGeometryIndex.fromOsm(data);
    // Kotak kecil di barat (lon -0.005..0.005) → hanya residential (lon 0..0.02),
    // track (lon 0.02..0.03) di luar.
    final hit = idx.queryBounds(-0.005, -0.005, 0.005, 0.005);
    expect(hit.map((r) => r.highway), ['residential']);
  });

  test('queryBounds: kotak yang meleset → kosong', () {
    final idx = RoadGeometryIndex.fromOsm(data);
    final none = idx.queryBounds(1.0, 1.0, 2.0, 2.0);
    expect(none, isEmpty);
  });

  test('RoadPolyline menghitung bbox sendiri', () {
    final idx = RoadGeometryIndex.fromOsm(data);
    final res = idx.roads.firstWhere((r) => r.highway == 'residential');
    expect(res.minLon, 0.0);
    expect(res.maxLon, 0.02);
    expect(res.minLat, 0.0);
    expect(res.maxLat, 0.0);
  });
}
