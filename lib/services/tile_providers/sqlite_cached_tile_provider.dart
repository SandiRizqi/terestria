import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:ui' as ui;
import '../tile_cache_sqlite_service.dart';
import '../tile_download_manager.dart';

/// Custom TileProvider dengan SQLite cache - SUPER CEPAT!
/// Untuk mode offline, tile langsung dimuat dari SQLite tanpa delay
/// Dengan download manager yang mengelola concurrent requests dan retry
class SqliteCachedTileProvider extends TileProvider {
  final TileCacheSqliteService _cacheService;
  final TileDownloadManager _downloadManager;
  final String basemapId;
  final Duration maxStale;

  SqliteCachedTileProvider({
    required this.basemapId,
    this.maxStale = const Duration(days: 30),
  })  : _cacheService = TileCacheSqliteService(),
        _downloadManager = TileDownloadManager();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return SqliteCachedTileImage(
      url: getTileUrl(coordinates, options),
      coordinates: coordinates,
      basemapId: basemapId,
      cacheService: _cacheService,
      downloadManager: _downloadManager,
    );
  }
}

/// Custom ImageProvider untuk SQLite cache dengan download manager
class SqliteCachedTileImage extends ImageProvider<SqliteCachedTileImage> {
  final String url;
  final TileCoordinates coordinates;
  final String basemapId;
  final TileCacheSqliteService cacheService;
  final TileDownloadManager downloadManager;

  const SqliteCachedTileImage({
    required this.url,
    required this.coordinates,
    required this.basemapId,
    required this.cacheService,
    required this.downloadManager,
  });

  @override
  Future<SqliteCachedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<SqliteCachedTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
      SqliteCachedTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<SqliteCachedTileImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
      SqliteCachedTileImage key, ImageDecoderCallback decode) async {
    final z = coordinates.z.toInt();
    final x = coordinates.x.toInt();
    final y = coordinates.y.toInt();

    try {
      // 1. PRIORITAS UTAMA: Coba load dari cache DULU - SUPER CEPAT!
      final cachedTile = await cacheService.getTile(
        basemapId: basemapId,
        z: z,
        x: x,
        y: y,
      );

      if (cachedTile != null) {
        // ✅ Cache hit! Langsung return tanpa download
        final buffer = await ui.ImmutableBuffer.fromUint8List(cachedTile);
        return decode(buffer);
      }

      // Check if this is a PDF basemap (URL is empty, starts with sqlite:// or overlay://)
      final isPdfBasemap =
          url.isEmpty || url.startsWith('sqlite://') || url.startsWith('overlay://');

      if (isPdfBasemap) {
        // PDF basemap: tiles should be in SQLite OR use overlay mode
        // If overlay mode (overlay://), this provider shouldn't be used at all
        // Only log once per zoom level to avoid spam
        if (z >= 16) {
          // Log only for high zoom levels (likely out of bounds)
          print(
              '⚠️ PDF basemap tile z=$z, x=$x, y=$y not in cache (zoom level may be too high)');
        }
        return _createPlaceholderTile(decode);
      }

      // 2. TMS basemap: Download from URL using download manager
      print('⚠️ CACHE MISS! Tile z=$z, x=$x, y=$y - adding to download queue');

      final bytes = await downloadManager.downloadTile(
        url: url,
        z: z,
        x: x,
        y: y,
        isVisible: true, // Assume visible since it's being loaded
      );

      if (bytes != null) {
        print('📥 Downloaded tile z=$z, x=$x, y=$y (${bytes.length} bytes)');

        // Save to cache asynchronously dengan proper error handling
        try {
          await cacheService.saveTile(
            basemapId: basemapId,
            z: z,
            x: x,
            y: y,
            tileData: bytes,
          );
          print('💾 Saved tile z=$z, x=$x, y=$y to cache');
        } catch (saveError) {
          print('❌ Error saving tile to cache: $saveError');
          // Continue even if save fails
        }

        // Return downloaded tile
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return decode(buffer);
      } else {
        // Download failed after retries
        print('❌ Failed to download tile z=$z, x=$x, y=$y - using placeholder');
        return _createPlaceholderTile(decode);
      }
    } catch (e) {
      print('❌ Critical error loading tile z=$z, x=$x, y=$y: $e');
      return _createPlaceholderTile(decode);
    }
  }

  /// Create a transparent placeholder tile for offline mode
  Future<ui.Codec> _createPlaceholderTile(ImageDecoderCallback decode) async {
    // Create 256x256 transparent PNG (1x1 pixel stretched)
    final placeholderBytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82, // IEND chunk
    ]);

    final buffer = await ui.ImmutableBuffer.fromUint8List(placeholderBytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SqliteCachedTileImage &&
        other.url == url &&
        other.basemapId == basemapId &&
        other.coordinates == coordinates;
  }

  @override
  int get hashCode => Object.hash(url, basemapId, coordinates);
}
