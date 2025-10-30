import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../tile_cache_sqlite_service.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Tile Provider untuk PDF Basemap yang menggunakan SQLite cache
class PdfSqliteTileProvider extends TileProvider {
  final String basemapId;
  final TileCacheSqliteService _cacheService = TileCacheSqliteService();

  PdfSqliteTileProvider(this.basemapId);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final z = coordinates.z.round();
    final x = coordinates.x.round();
    final y = coordinates.y.round();
    
    return PdfSqliteImageProvider(
      basemapId: basemapId,
      z: z,
      x: x,
      y: y,
      cacheService: _cacheService,
    );
  }
}

class PdfSqliteImageProvider extends ImageProvider<PdfSqliteImageProvider> {
  final String basemapId;
  final int z;
  final int x;
  final int y;
  final TileCacheSqliteService cacheService;

  const PdfSqliteImageProvider({
    required this.basemapId,
    required this.z,
    required this.x,
    required this.y,
    required this.cacheService,
  });

  @override
  Future<PdfSqliteImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<PdfSqliteImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadBuffer(
    PdfSqliteImageProvider key,
    DecoderBufferCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: '$basemapId/$z/$x/$y',
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>('Image provider', this);
        yield DiagnosticsProperty<PdfSqliteImageProvider>('Image key', key);
      },
    );
  }

  Future<ui.Codec> _loadAsync(
    PdfSqliteImageProvider key,
    DecoderBufferCallback decode,
  ) async {
    try {
      assert(key == this);

      // Get tile from SQLite cache
      final tileData = await cacheService.getTile(
        basemapId: basemapId,
        z: z,
        x: x,
        y: y,
      );

      if (tileData != null) {
        final buffer = await ui.ImmutableBuffer.fromUint8List(tileData);
        return decode(buffer);
      }

      // Return transparent tile if not found
      final transparentPng = _createTransparentPng();
      final buffer = await ui.ImmutableBuffer.fromUint8List(transparentPng);
      return decode(buffer);
    } catch (e) {
      print('Error loading PDF tile $basemapId/$z/$x/$y: $e');
      final transparentPng = _createTransparentPng();
      final buffer = await ui.ImmutableBuffer.fromUint8List(transparentPng);
      return decode(buffer);
    }
  }

  Uint8List _createTransparentPng() {
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is PdfSqliteImageProvider &&
      other.basemapId == basemapId &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(basemapId, z, x, y);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'PdfSqliteImageProvider')}("$basemapId/$z/$x/$y")';
}
