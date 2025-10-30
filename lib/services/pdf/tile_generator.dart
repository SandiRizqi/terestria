import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'pdf_georef_extractor.dart';
import '../tile_cache_sqlite_service.dart';

class TileGeneratorConfig {
  final int? minZoom;
  final int? maxZoom;
  final int dpi;
  final PdfGeoreferencing? georef;

  const TileGeneratorConfig({
    this.minZoom,
    this.maxZoom,
    this.dpi = 150,
    this.georef,
  });
}

class _TileProcessParams {
  final img.Image image;
  final int zoom;
  final int baseZoom;
  final int tileSize;

  _TileProcessParams(this.image, this.zoom, this.baseZoom, this.tileSize);
}

img.Image _resizeImage(_TileProcessParams params) {
  final zoomScale = math.pow(2, params.zoom - params.baseZoom).toDouble();
  final width = (params.image.width * zoomScale).round();
  final height = (params.image.height * zoomScale).round();
  return img.copyResize(
    params.image,
    width: width,
    height: height,
    interpolation: img.Interpolation.average,
  );
}

class TileGenerator {
  final _tileCacheService = TileCacheSqliteService();
  final _georefExtractor = PdfGeorefExtractor();

  /// Generate TMS tiles from PDF - Optimized for PDF extent only with SQLite cache
  Future<void> generateTiles({
    required String pdfPath,
    required String basemapId,
    required Function(double progress, String status) onProgress,
    TileGeneratorConfig config = const TileGeneratorConfig(),
  }) async {
    try {
      onProgress(0.0, 'Extracting georeferencing...');

      // Extract georeferencing from PDF
      PdfGeoreferencing? georef = config.georef;
      if (georef == null) {
        georef = await _georefExtractor.extractGeoreferencing(pdfPath);
        if (georef == null) {
          throw Exception('Could not extract georeferencing from PDF');
        }
      }

      print('✓ PDF Extent: ${georef.toString()}');

      // Calculate optimal zoom levels
      final zoomLevels = georef.calculateOptimalZoomLevels();
      final minZoom = config.minZoom ?? zoomLevels['minZoom']!;
      final maxZoom = config.maxZoom ?? zoomLevels['maxZoom']!;
      final baseZoom = zoomLevels['baseZoom']!;

      print('✓ Zoom levels: min=$minZoom, base=$baseZoom, max=$maxZoom');

      onProgress(0.1, 'Rendering PDF at ${config.dpi} DPI...');

      final pdfBytes = await File(pdfPath).readAsBytes();
      final page = await Printing.raster(pdfBytes, pages: [0], dpi: config.dpi.toDouble()).first;

      onProgress(0.2, 'Converting to image...');

      final imageBytes = await page.toPng();
      final image = img.decodeImage(imageBytes);

      if (image == null) throw Exception('Failed to decode image');

      print('✓ Image size: ${image.width}x${image.height}');

      onProgress(0.3, 'Generating tiles for extent only...');

      await _processTilesWithSqlite(
        image: image,
        basemapId: basemapId,
        georef: georef,
        minZoom: minZoom,
        maxZoom: maxZoom,
        baseZoom: baseZoom,
        onProgress: onProgress,
      );

      onProgress(1.0, 'Complete!');
    } catch (e) {
      onProgress(-1.0, 'Error: ${e.toString()}');
      rethrow;
    }
  }

  Future<void> _processTilesWithSqlite({
    required img.Image image,
    required String basemapId,
    required PdfGeoreferencing georef,
    required int minZoom,
    required int maxZoom,
    required int baseZoom,
    required Function(double progress, String status) onProgress,
  }) async {
    const tileSize = 256;

    // Calculate total tiles
    int totalTiles = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final tiles = _getTileRangeForZoom(georef, z, tileSize);
      totalTiles += tiles['count']!;
    }

    print('✓ Total tiles to generate: $totalTiles');

    int processed = 0;

    for (int zoom = minZoom; zoom <= maxZoom; zoom++) {
      final tileRange = _getTileRangeForZoom(georef, zoom, tileSize);
      final minTileX = tileRange['minX']!;
      final maxTileX = tileRange['maxX']!;
      final minTileY = tileRange['minY']!;
      final maxTileY = tileRange['maxY']!;
      final tilesCount = tileRange['count']!;

      onProgress(
        0.3 + (processed / totalTiles) * 0.65,
        'Zoom $zoom: ${tilesCount} tiles',
      );

      // Resize image for this zoom level
      final scaledImage = await compute<_TileProcessParams, img.Image>(
        _resizeImage,
        _TileProcessParams(image, zoom, baseZoom, tileSize),
      );

      print('✓ Zoom $zoom: Image scaled to ${scaledImage.width}x${scaledImage.height}');

      // Calculate which part of the scaled image corresponds to the tile range
      final worldTilesAtZoom = math.pow(2, zoom);
      final imageToTileScaleX = scaledImage.width / (maxTileX - minTileX + 1);
      final imageToTileScaleY = scaledImage.height / (maxTileY - minTileY + 1);

      // Generate tiles in batches to avoid overwhelming database
      const batchSize = 50;
      List<Future> writeFutures = [];

      for (int tileX = minTileX; tileX <= maxTileX; tileX++) {
        for (int tileY = minTileY; tileY <= maxTileY; tileY++) {
          // Calculate position in scaled image
          final imgX = ((tileX - minTileX) * imageToTileScaleX).round();
          final imgY = ((tileY - minTileY) * imageToTileScaleY).round();

          // Extract and save tile
          final tile = _extractTileFromPosition(
            scaledImage,
            imgX,
            imgY,
            imageToTileScaleX.round(),
            imageToTileScaleY.round(),
            tileSize,
          );

          final tileData = img.encodePng(tile);

          // Save to SQLite cache
          writeFutures.add(
            _tileCacheService.saveTile(
              basemapId: basemapId,
              z: zoom,
              x: tileX,
              y: tileY,
              tileData: tileData,
            ),
          );

          processed++;

          // Process in batches
          if (writeFutures.length >= batchSize) {
            await Future.wait(writeFutures);
            writeFutures.clear();

            final progress = 0.3 + (processed / totalTiles) * 0.65;
            onProgress(progress, 'Tile $processed/$totalTiles');
          }
        }
      }

      // Process remaining tiles
      if (writeFutures.isNotEmpty) {
        await Future.wait(writeFutures);
        final progress = 0.3 + (processed / totalTiles) * 0.65;
        onProgress(progress, 'Tile $processed/$totalTiles');
      }
    }
  }

  /// Calculate tile range for a given zoom level based on georeferencing
  Map<String, int> _getTileRangeForZoom(PdfGeoreferencing georef, int zoom, int tileSize) {
    final n = math.pow(2, zoom);

    // Convert lat/lon to tile coordinates
    final minTileX = _lonToTileX(georef.minLon, zoom);
    final maxTileX = _lonToTileX(georef.maxLon, zoom);
    final minTileY = _latToTileY(georef.maxLat, zoom); // Note: Y is inverted
    final maxTileY = _latToTileY(georef.minLat, zoom);

    final tilesX = (maxTileX - minTileX + 1);
    final tilesY = (maxTileY - minTileY + 1);

    return {
      'minX': minTileX,
      'maxX': maxTileX,
      'minY': minTileY,
      'maxY': maxTileY,
      'count': tilesX * tilesY,
    };
  }

  /// Convert longitude to tile X coordinate
  int _lonToTileX(double lon, int zoom) {
    final n = math.pow(2, zoom);
    return ((lon + 180.0) / 360.0 * n).floor();
  }

  /// Convert latitude to tile Y coordinate (Web Mercator)
  int _latToTileY(double lat, int zoom) {
    final n = math.pow(2, zoom);
    final latRad = lat * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n).floor();
  }

  img.Image _extractTileFromPosition(
    img.Image source,
    int x,
    int y,
    int width,
    int height,
    int tileSize,
  ) {
    // Calculate actual crop dimensions
    final cropWidth = math.min(width, source.width - x);
    final cropHeight = math.min(height, source.height - y);

    if (cropWidth <= 0 || cropHeight <= 0 || x < 0 || y < 0) {
      // Return blank tile if out of bounds
      return img.Image(width: tileSize, height: tileSize);
    }

    // Crop the tile
    final cropped = img.copyCrop(
      source,
      x: x,
      y: y,
      width: cropWidth,
      height: cropHeight,
    );

    // Resize to exact tile size if needed
    if (cropped.width != tileSize || cropped.height != tileSize) {
      return img.copyResize(
        cropped,
        width: tileSize,
        height: tileSize,
        interpolation: img.Interpolation.linear,
      );
    }

    return cropped;
  }

  /// Get georeferencing info for a basemap (for display purposes)
  Future<PdfGeoreferencing?> getGeoreferencing(String pdfPath) async {
    return await _georefExtractor.extractGeoreferencing(pdfPath);
  }

  /// Delete tiles from SQLite cache
  Future<void> deleteTiles(String basemapId) async {
    try {
      await _tileCacheService.clearCache(basemapId);
      print('✓ Tiles deleted for $basemapId');
    } catch (e) {
      print('❌ Error deleting tiles: $e');
    }
  }

  /// Legacy method - no longer used (tiles now in SQLite)
  @Deprecated('Tiles are now stored in SQLite cache')
  Future<String> getBasePath(String basemapId) async {
    return 'sqlite://$basemapId';
  }

  /// Legacy method - no longer used (tiles now in SQLite)
  @Deprecated('Tiles are now stored in SQLite cache')
  Future<String> getLocalTmsUrl(String basemapId) async {
    return 'sqlite://$basemapId/{z}/{x}/{y}';
  }
}
