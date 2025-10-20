import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';


class TileGeneratorConfig {
  final int minZoom;
  final int maxZoom;
  final int dpi;

  const TileGeneratorConfig({
    this.minZoom = 14,
    this.maxZoom = 18,
    this.dpi = 150,
  });
}

class _TileProcessParams {
  final img.Image image;
  final int zoom;
  final int tileSize;

  _TileProcessParams(this.image, this.zoom, this.tileSize);
}

img.Image _resizeImage(_TileProcessParams params) {
  final zoomScale = pow(2, params.zoom - 14).toDouble(); // baseZoom = 14
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
  /// Generate TMS tiles from PDF - OPTIMIZED for local PDF area only
  Future<void> generateTiles({
    required String pdfPath,
    required String basemapId,
    required Function(double progress, String status) onProgress,
    TileGeneratorConfig config = const TileGeneratorConfig(),
  }) async {
    try {
      onProgress(0.0, 'Loading PDF...');

      final appDir = await getApplicationDocumentsDirectory();
      final tilesDir = Directory('${appDir.path}/basemap_tiles/$basemapId');
      
      if (await tilesDir.exists()) {
        await tilesDir.delete(recursive: true);
      }
      await tilesDir.create(recursive: true);

      onProgress(0.1, 'Rendering PDF page...');

      final pdfBytes = await File(pdfPath).readAsBytes();
      final page = await Printing.raster(pdfBytes, pages: [0], dpi: config.dpi.toDouble()).first;

      onProgress(0.2, 'Converting to image...');

      final imageBytes = await page.toPng();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) throw Exception('Failed to decode image');

      onProgress(0.3, 'Generating tiles for PDF area only...');

      await _processTiles(image, tilesDir, onProgress, config);

      onProgress(1.0, 'Complete!');
    } catch (e) {
      onProgress(-1.0, 'Error: ${e.toString()}');
      rethrow;
    }
  }

  Future<void> _processTiles(
    img.Image image,
    Directory tilesDir,
    Function(double progress, String status) onProgress,
    TileGeneratorConfig config,
  ) async {
    const tileSize = 256;

    int totalTiles = 0;
    Map<int, int> tilesPerZoom = {};
    for (int z = config.minZoom; z <= config.maxZoom; z++) {
      final tilesCount = _getTilesCount(image, z, tileSize, config.minZoom);
      tilesPerZoom[z] = tilesCount;
      totalTiles += tilesCount;
    }

    int processed = 0;

    for (int zoom = config.minZoom; zoom <= config.maxZoom; zoom++) {
      final zoomScale = pow(2, zoom - config.minZoom).toDouble();
      final scaledWidth = (image.width * zoomScale).round();
      final scaledHeight = (image.height * zoomScale).round();
      final tilesX = (scaledWidth / tileSize).ceil();
      final tilesY = (scaledHeight / tileSize).ceil();

      onProgress(
        0.3 + (processed / totalTiles) * 0.65,
        'Zoom $zoom: ${tilesX}x$tilesY tiles',
      );

      // Resize image sekali per zoom level menggunakan compute agar tidak blocking UI
      final scaledImage = await compute<_TileProcessParams, img.Image>(
        _resizeImage,
        _TileProcessParams(image, zoom, tileSize),
      );

      final zoomDir = Directory('${tilesDir.path}/$zoom');
      await zoomDir.create(recursive: true);

      for (int x = 0; x < tilesX; x++) {
        final xDir = Directory('${zoomDir.path}/$x');
        await xDir.create(recursive: true);

        List<Future> writeFutures = [];
        for (int y = 0; y < tilesY; y++) {
          final tile = _extractTile(scaledImage, x, y, tileSize);
          final tileFile = File('${xDir.path}/$y.png');
          writeFutures.add(tileFile.writeAsBytes(img.encodePng(tile)));

          processed++;
          if (processed % 50 == 0 || processed == totalTiles) {
            final progress = 0.3 + (processed / totalTiles) * 0.65;
            onProgress(progress, 'Tile $processed/$totalTiles');
          }
        }
        await Future.wait(writeFutures);
      }
    }
  }

  int _getTilesCount(img.Image image, int zoom, int tileSize, int baseZoom) {
    final zoomScale = pow(2, zoom - baseZoom).toDouble();
    final scaledWidth = (image.width * zoomScale).round();
    final scaledHeight = (image.height * zoomScale).round();
    final tilesX = (scaledWidth / tileSize).ceil();
    final tilesY = (scaledHeight / tileSize).ceil();
    return tilesX * tilesY;
  }

  img.Image _extractTile(img.Image source, int tileX, int tileY, int tileSize) {
    final x = tileX * tileSize;
    final y = tileY * tileSize;
    
    // Calculate actual crop dimensions
    final cropWidth = min(tileSize, source.width - x);
    final cropHeight = min(tileSize, source.height - y);

    if (cropWidth <= 0 || cropHeight <= 0) {
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

    // If tile is smaller than standard size, pad it
    if (cropped.width < tileSize || cropped.height < tileSize) {
      final padded = img.Image(width: tileSize, height: tileSize);
      img.compositeImage(padded, cropped, dstX: 0, dstY: 0);
      return padded;
    }

    return cropped;
  }

  /// Get local tiles base path
  Future<String> getBasePath(String basemapId) async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/basemap_tiles/$basemapId';
  }

  /// Get local TMS URL template (for display purposes only)
  Future<String> getLocalTmsUrl(String basemapId) async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/basemap_tiles/$basemapId/{z}/{x}/{y}.png';
  }

  /// Delete tiles directory
  Future<void> deleteTiles(String basemapId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tilesDir = Directory('${appDir.path}/basemap_tiles/$basemapId');
      
      if (await tilesDir.exists()) {
        await tilesDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
