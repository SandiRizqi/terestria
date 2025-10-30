import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import '../tile_cache_sqlite_service.dart';

/// Custom TileProvider dengan SQLite cache - SUPER CEPAT!
/// Untuk mode offline, tile langsung dimuat dari SQLite tanpa delay
class SqliteCachedTileProvider extends TileProvider {
  final TileCacheSqliteService _cacheService;
  final String basemapId;
  final Duration maxStale;
  final http.Client? httpClient;

  SqliteCachedTileProvider({
    required this.basemapId,
    this.maxStale = const Duration(days: 30),
    this.httpClient,
  }) : _cacheService = TileCacheSqliteService();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return SqliteCachedTileImage(
      url: getTileUrl(coordinates, options),
      coordinates: coordinates,
      basemapId: basemapId,
      cacheService: _cacheService,
      httpClient: httpClient,
    );
  }
}

/// Custom ImageProvider untuk SQLite cache
class SqliteCachedTileImage extends ImageProvider<SqliteCachedTileImage> {
  final String url;
  final TileCoordinates coordinates;
  final String basemapId;
  final TileCacheSqliteService cacheService;
  final http.Client? httpClient;

  const SqliteCachedTileImage({
    required this.url,
    required this.coordinates,
    required this.basemapId,
    required this.cacheService,
    this.httpClient,
  });

  @override
  Future<SqliteCachedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<SqliteCachedTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(SqliteCachedTileImage key, ImageDecoderCallback decode) {
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

  Future<ui.Codec> _loadAsync(SqliteCachedTileImage key, ImageDecoderCallback decode) async {
    final z = coordinates.z.toInt();
    final x = coordinates.x.toInt();
    final y = coordinates.y.toInt();
    
    try {
      // 1. PRIORITAS UTAMA: Coba load dari cache DULU - SUPER CEPAT!
      print('🔍 Loading tile z=$z, x=$x, y=$y for basemap=$basemapId');
      
      final cachedTile = await cacheService.getTile(
        basemapId: basemapId,
        z: z,
        x: x,
        y: y,
      );

      if (cachedTile != null) {
        // ✅ Cache hit! Langsung return tanpa download
        print('✅ CACHE HIT! Tile z=$z, x=$x, y=$y loaded from cache (${cachedTile.length} bytes)');
        final buffer = await ui.ImmutableBuffer.fromUint8List(cachedTile);
        return decode(buffer);
      }

      print('⚠️ CACHE MISS! Tile z=$z, x=$x, y=$y not in cache, attempting download...');

      // 2. Jika tidak ada di cache, coba download (dengan error handling)
      try {
        final client = httpClient ?? http.Client();
        final response = await client.get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'GeoformApp/1.0',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          print('📥 Downloaded tile z=$z, x=$x, y=$y (${bytes.length} bytes)');
          
          // Save to cache asynchronously dengan proper error handling
          try {
            await cacheService.saveTile(
              basemapId: basemapId,
              z: z,
              x: x,
              y: y,
              tileData: Uint8List.fromList(bytes),
            );
            print('💾 Saved tile z=$z, x=$x, y=$y to cache');
          } catch (saveError) {
            print('❌ Error saving tile to cache: $saveError');
            // Continue even if save fails
          }

          // Return downloaded tile
          final buffer = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes));
          return decode(buffer);
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (downloadError) {
        // Download failed (offline atau network error)
        print('❌ Download failed for tile z=$z, x=$x, y=$y: $downloadError');
        
        // Return transparent placeholder tile untuk offline mode
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
