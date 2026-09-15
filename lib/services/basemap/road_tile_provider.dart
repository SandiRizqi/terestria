import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/road_vector_style.dart';
import '../tile_cache_sqlite_service.dart';
import 'road_geometry_index.dart';

/// Ukuran sisi tile (px). Standar slippy-map.
const int kRoadTileSize = 256;

/// TileProvider yang **merender jaringan jalan menjadi tile raster di device
/// secara lazy** lalu meng-cache-nya di SQLite (pola [SqliteCachedTileProvider]).
///
/// Alur `getImage`:
///   1. Cache hit (`basemapId = roads_<companyId>`) → decode langsung.
///   2. Miss → query [RoadGeometryIndex] untuk ruas yang menyentuh tile →
///      proyeksi ke piksel → gambar garis (warna/tebal per [RoadVectorStyle]) →
///      PNG → simpan cache → decode.
///
/// Tak ada jaringan; murni on-device. Display akhirnya seringan basemap raster.
class RoadTileProvider extends TileProvider {
  final RoadGeometryIndex index;
  final String basemapId;
  final TileCacheSqliteService _cache;

  RoadTileProvider({required this.index, required this.basemapId})
      : _cache = TileCacheSqliteService();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _RoadTileImage(
      index: index,
      basemapId: basemapId,
      cache: _cache,
      coordinates: coordinates,
    );
  }

  // ─── Matematika Web-Mercator (murni, teruji) ─────────────────────────────

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

  /// Batas geografis tile: `[west, south, east, north]` (derajat).
  static List<double> tileBounds(int z, int x, int y) {
    final n = 1 << z; // 2^z
    double lon(int xx) => xx / n * 360.0 - 180.0;
    double lat(int yy) =>
        math.atan(_sinh(math.pi * (1 - 2 * yy / n))) * 180.0 / math.pi;
    return [lon(x), lat(y + 1), lon(x + 1), lat(y)];
  }

  /// Proyeksikan [p] ke piksel di dalam tile (z/x/y); origin (0,0) = pojok
  /// kiri-atas (NW), (256,256) = kanan-bawah (SE). Nilai di luar 0..256 = di
  /// luar tile (berguna untuk garis yang melintasi tepi).
  static Offset project(LatLng p, int z, int x, int y) {
    final n = 1 << z;
    final latRad = p.latitude * math.pi / 180.0;
    final worldX = (p.longitude + 180.0) / 360.0 * n;
    final worldY =
        (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            n;
    return Offset(
      (worldX - x) * kRoadTileSize,
      (worldY - y) * kRoadTileSize,
    );
  }

  /// Render satu tile jaringan jalan → PNG bytes. Dipisah agar bisa dipakai
  /// ulang; memerlukan dart:ui (dijalankan di device, bukan unit test murni).
  static Future<Uint8List> renderTile(
      RoadGeometryIndex index, int z, int x, int y) async {
    final b = tileBounds(z, x, y); // west, south, east, north
    final roads = index.queryBounds(b[1], b[0], b[3], b[2]);

    final recorder = ui.PictureRecorder();
    final canvas =
        ui.Canvas(recorder, const Rect.fromLTWH(0, 0, 256, 256));

    for (final r in roads) {
      final style =
          RoadVectorStyle.forHighway(r.highway) ?? RoadVectorStyle.defaultStyle;
      final paint = Paint()
        ..color = style.color
        ..strokeWidth = style.strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      final path = ui.Path();
      var moved = false;
      for (final p in r.points) {
        final o = project(p, z, x, y);
        if (!moved) {
          path.moveTo(o.dx, o.dy);
          moved = true;
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(kRoadTileSize, kRoadTileSize);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RoadTileImage extends ImageProvider<_RoadTileImage> {
  final RoadGeometryIndex index;
  final String basemapId;
  final TileCacheSqliteService cache;
  final TileCoordinates coordinates;

  const _RoadTileImage({
    required this.index,
    required this.basemapId,
    required this.cache,
    required this.coordinates,
  });

  @override
  Future<_RoadTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_RoadTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
      _RoadTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      debugLabel: '$basemapId/${coordinates.z}/${coordinates.x}/${coordinates.y}',
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final z = coordinates.z.toInt();
    final x = coordinates.x.toInt();
    final y = coordinates.y.toInt();

    // 1. Cache hit.
    final cached = await cache.getTile(basemapId: basemapId, z: z, x: x, y: y);
    if (cached != null) {
      return decode(await ui.ImmutableBuffer.fromUint8List(cached));
    }

    // 2. Miss → render + simpan (transparan pun di-cache agar tak render ulang).
    final png = await RoadTileProvider.renderTile(index, z, x, y);
    cache
        .saveTile(basemapId: basemapId, z: z, x: x, y: y, tileData: png)
        .catchError((_) {});
    return decode(await ui.ImmutableBuffer.fromUint8List(png));
  }

  @override
  bool operator ==(Object other) =>
      other is _RoadTileImage &&
      other.basemapId == basemapId &&
      other.coordinates == coordinates;

  @override
  int get hashCode => Object.hash(basemapId, coordinates);
}
