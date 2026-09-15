import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/road_vector_style.dart';
import '../routing_dart/pbf_reader.dart';

/// Satu ruas jalan siap gambar: daftar titik + kelas `highway` + bbox
/// (dipra-hitung untuk culling cepat per tile).
class RoadPolyline {
  final List<LatLng> points;
  final String highway;
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  RoadPolyline._(
      this.points, this.highway, this.minLat, this.minLon, this.maxLat, this.maxLon);

  factory RoadPolyline(List<LatLng> points, String highway) {
    var minLat = double.infinity, minLon = double.infinity;
    var maxLat = -double.infinity, maxLon = -double.infinity;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    return RoadPolyline._(points, highway, minLat, minLon, maxLat, maxLon);
  }
}

/// Index geometri jaringan jalan (in-memory) untuk basemap raster.
///
/// Dibangun dari [OsmData] (hasil `pbf_reader`). Hanya menyimpan way yang
/// benar-benar digambar (kelas kendaraan; pejalan-kaki dilewati lewat
/// [RoadVectorStyle.forHighway]) dan punya ≥2 titik valid. [queryBounds]
/// mengembalikan ruas yang bbox-nya beririsan dengan kotak (untuk culling
/// per tile sebelum rasterisasi).
class RoadGeometryIndex {
  final List<RoadPolyline> roads;
  const RoadGeometryIndex(this.roads);

  bool get isEmpty => roads.isEmpty;
  int get length => roads.length;

  factory RoadGeometryIndex.fromOsm(OsmData data) {
    final nodeById = <int, LatLng>{};
    for (final n in data.nodes) {
      nodeById[n.id] = LatLng(n.lat, n.lon);
    }

    final roads = <RoadPolyline>[];
    for (final w in data.ways) {
      final hw = w.tags['highway'];
      // Lewati kelas non-jalan / tanpa highway (pusat keputusan di style).
      if (RoadVectorStyle.forHighway(hw) == null) continue;

      final pts = <LatLng>[];
      for (final ref in w.refs) {
        final p = nodeById[ref];
        if (p != null) pts.add(p);
      }
      if (pts.length < 2) continue; // butuh minimal satu segmen
      roads.add(RoadPolyline(pts, hw!));
    }
    return RoadGeometryIndex(roads);
  }

  /// Ruas yang bbox-nya beririsan dengan kotak [minLat,minLon]–[maxLat,maxLon].
  /// Uji AABB sederhana — cukup untuk culling; klip presisi terjadi saat raster.
  List<RoadPolyline> queryBounds(
      double minLat, double minLon, double maxLat, double maxLon) {
    return roads
        .where((r) =>
            r.minLat <= maxLat &&
            r.maxLat >= minLat &&
            r.minLon <= maxLon &&
            r.maxLon >= minLon)
        .toList();
  }
}

/// Parse file `.pbf` di isolate → [RoadGeometryIndex]. Dipakai saat data jalan
/// aktif berubah; jangan panggil di UI thread untuk file besar.
Future<RoadGeometryIndex> buildRoadIndexFromFile(String path) =>
    compute(_indexFromPath, path);

RoadGeometryIndex _indexFromPath(String path) {
  final Uint8List bytes = File(path).readAsBytesSync();
  final data = readOsmPbf(bytes);
  return RoadGeometryIndex.fromOsm(data);
}
