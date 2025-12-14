import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../utils/lat_lng_bounds.dart';
import 'tile_download_manager.dart';
import 'tile_cache_sqlite_service.dart';

/// Service untuk mengelola bulk download tiles untuk offline use
class OfflineBasemapDownloadService {
  static final OfflineBasemapDownloadService _instance = OfflineBasemapDownloadService._internal();
  factory OfflineBasemapDownloadService() => _instance;
  OfflineBasemapDownloadService._internal();

  final TileDownloadManager _downloadManager = TileDownloadManager();
  final TileCacheSqliteService _cacheService = TileCacheSqliteService();

  // Download state
  bool _isDownloading = false;
  bool _isCancelled = false;
  int _totalTiles = 0;
  int _downloadedTiles = 0;
  int _failedTiles = 0;
  String _currentStatus = '';
  
  // Progress callbacks
  Function(double progress, String status)? _onProgress;
  Function(String error)? _onError;
  Function()? _onComplete;
  Function()? _onCancelled;

  /// Get download status
  bool get isDownloading => _isDownloading;
  double get progress => _totalTiles > 0 ? _downloadedTiles / _totalTiles : 0.0;
  String get currentStatus => _currentStatus;

  /// Calculate number of tiles needed for given bounds and zoom levels
  static int calculateTileCount({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) {
    int totalTiles = 0;
    
    for (int z = minZoom; z <= maxZoom; z++) {
      final tiles = _getTilesForBounds(bounds, z);
      totalTiles += tiles.length;
    }
    
    return totalTiles;
  }

  /// Estimate download size in MB based on actual sample tiles
  static Future<double> estimateDownloadSize({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required String urlTemplate,
  }) async {
    final tileCount = calculateTileCount(
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    
    // Sample actual tile sizes from the URL
    final avgTileSizeKB = await _sampleAverageTileSize(
      bounds: bounds,
      zoom: minZoom, // Use minZoom for sampling
      urlTemplate: urlTemplate,
    );
    
    debugPrint('📊 Estimated average tile size: ${avgTileSizeKB.toStringAsFixed(2)} KB');
    return (tileCount * avgTileSizeKB) / 1024; // Convert to MB
  }

  /// Sample random tiles to estimate average tile size
  static Future<double> _sampleAverageTileSize({
    required LatLngBounds bounds,
    required int zoom,
    required String urlTemplate,
    int sampleCount = 5,
  }) async {
    try {
      // Get all tiles for the bounds at this zoom level
      final allTiles = _getTilesForBounds(bounds, zoom);
      
      if (allTiles.isEmpty) {
        debugPrint('⚠️ No tiles found for sampling, using default 15KB');
        return 15.0; // Default fallback
      }
      
      // Randomly sample tiles (max 5 samples)
      final random = math.Random();
      final samplesToTake = math.min(sampleCount, allTiles.length);
      final sampledTiles = <TileCoordinate>[];
      
      // Get random unique tiles
      final availableIndices = List<int>.generate(allTiles.length, (i) => i);
      for (int i = 0; i < samplesToTake; i++) {
        final randomIndex = availableIndices[random.nextInt(availableIndices.length)];
        sampledTiles.add(allTiles[randomIndex]);
        availableIndices.remove(randomIndex);
      }
      
      debugPrint('🎲 Sampling $samplesToTake random tiles from ${allTiles.length} total tiles...');
      
      // Download sample tiles and measure their sizes
      final downloadManager = TileDownloadManager();
      final tileSizes = <int>[];
      
      for (final tile in sampledTiles) {
        try {
          final url = urlTemplate
              .replaceAll('{z}', tile.z.toString())
              .replaceAll('{x}', tile.x.toString())
              .replaceAll('{y}', tile.y.toString());
          
          final bytes = await downloadManager.downloadTile(
            url: url,
            z: tile.z,
            x: tile.x,
            y: tile.y,
            isVisible: false,
          );
          
          if (bytes != null && bytes.isNotEmpty) {
            tileSizes.add(bytes.length);
            debugPrint('   📦 Tile z=${tile.z},x=${tile.x},y=${tile.y}: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
          }
        } catch (e) {
          debugPrint('   ⚠️ Failed to sample tile z=${tile.z},x=${tile.x},y=${tile.y}: $e');
        }
      }
      
      if (tileSizes.isEmpty) {
        debugPrint('⚠️ No tiles successfully sampled, using default 15KB');
        return 15.0; // Default fallback
      }
      
      // Calculate average size in KB
      final avgBytes = tileSizes.reduce((a, b) => a + b) / tileSizes.length;
      final avgKB = avgBytes / 1024;
      
      debugPrint('✅ Sampled ${tileSizes.length} tiles, average size: ${avgKB.toStringAsFixed(2)} KB');
      return avgKB;
      
    } catch (e) {
      debugPrint('❌ Error sampling tile sizes: $e');
      return 15.0; // Default fallback
    }
  }

  /// Download tiles for visible map area
  Future<void> downloadTilesForArea({
    required String basemapId,
    required String urlTemplate,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    Function(double progress, String status)? onProgress,
    Function(String error)? onError,
    Function()? onComplete,
    Function()? onCancelled,
  }) async {
    if (_isDownloading) {
      onError?.call('Download already in progress');
      return;
    }

    // Reset state
    _isDownloading = true;
    _isCancelled = false;
    _downloadedTiles = 0;
    _failedTiles = 0;
    _onProgress = onProgress;
    _onError = onError;
    _onComplete = onComplete;
    _onCancelled = onCancelled;

    try {
      // Calculate total tiles
      _totalTiles = calculateTileCount(
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
      );

      debugPrint('🚀 Starting offline download: $_totalTiles tiles (zoom $minZoom-$maxZoom)');
      _updateProgress(0, 'Preparing download...');

      // Download tiles level by level
      for (int z = minZoom; z <= maxZoom; z++) {
        if (_isCancelled) {
          debugPrint('❌ Download cancelled by user');
          _isDownloading = false;
          onCancelled?.call();
          return;
        }

        final tiles = _getTilesForBounds(bounds, z);
        debugPrint('📥 Downloading zoom level $z: ${tiles.length} tiles');
        
        await _downloadZoomLevel(
          basemapId: basemapId,
          urlTemplate: urlTemplate,
          tiles: tiles,
          zoom: z,
        );
      }

      // Download complete
      _isDownloading = false;
      debugPrint('✅ Download complete! Downloaded: $_downloadedTiles, Failed: $_failedTiles');
      _updateProgress(1.0, 'Download complete! ($_downloadedTiles tiles)');
      
      // Small delay to show completion message
      await Future.delayed(const Duration(milliseconds: 500));
      onComplete?.call();

    } catch (e, stackTrace) {
      debugPrint('❌ Download error: $e');
      debugPrint('Stack trace: $stackTrace');
      _isDownloading = false;
      onError?.call('Download failed: $e');
    }
  }

  /// Download all tiles for a specific zoom level
  Future<void> _downloadZoomLevel({
    required String basemapId,
    required String urlTemplate,
    required List<TileCoordinate> tiles,
    required int zoom,
  }) async {
    const batchSize = 10; // Download 10 tiles at a time
    
    for (int i = 0; i < tiles.length; i += batchSize) {
      if (_isCancelled) return;

      final batch = tiles.skip(i).take(batchSize).toList();
      final futures = <Future>[];

      for (final tile in batch) {
        futures.add(_downloadSingleTile(
          basemapId: basemapId,
          urlTemplate: urlTemplate,
          tile: tile,
        ));
      }

      // Wait for batch to complete
      await Future.wait(futures);

      // Update progress
      final progress = _downloadedTiles / _totalTiles;
      _updateProgress(
        progress,
        'Downloading zoom $zoom: ${_downloadedTiles}/$_totalTiles tiles',
      );
    }
  }

  /// Download a single tile
  Future<void> _downloadSingleTile({
    required String basemapId,
    required String urlTemplate,
    required TileCoordinate tile,
  }) async {
    try {
      // Check if tile already exists in cache
      final existingTile = await _cacheService.getTile(
        basemapId: basemapId,
        z: tile.z,
        x: tile.x,
        y: tile.y,
      );

      if (existingTile != null) {
        // Tile already cached, skip download
        _downloadedTiles++;
        return;
      }

      // Build URL from template
      final url = urlTemplate
          .replaceAll('{z}', tile.z.toString())
          .replaceAll('{x}', tile.x.toString())
          .replaceAll('{y}', tile.y.toString());

      // Download tile
      final bytes = await _downloadManager.downloadTile(
        url: url,
        z: tile.z,
        x: tile.x,
        y: tile.y,
        isVisible: false, // Lower priority for bulk download
      );

      if (bytes != null) {
        // Save to cache
        await _cacheService.saveTile(
          basemapId: basemapId,
          z: tile.z,
          x: tile.x,
          y: tile.y,
          tileData: bytes,
        );
        _downloadedTiles++;
      } else {
        _failedTiles++;
      }
    } catch (e) {
      debugPrint('❌ Error downloading tile z=${tile.z},x=${tile.x},y=${tile.y}: $e');
      _failedTiles++;
    }
  }

  /// Get all tile coordinates for bounds at specific zoom level
  static List<TileCoordinate> _getTilesForBounds(LatLngBounds bounds, int zoom) {
    final tiles = <TileCoordinate>[];
    
    // Convert lat/lng bounds to tile coordinates
    final nwTile = _latLngToTile(bounds.northWest, zoom);
    final seTile = _latLngToTile(bounds.southEast, zoom);
    
    // Get min/max tile coordinates
    final minX = math.min(nwTile.x, seTile.x);
    final maxX = math.max(nwTile.x, seTile.x);
    final minY = math.min(nwTile.y, seTile.y);
    final maxY = math.max(nwTile.y, seTile.y);
    
    // Generate all tiles in the range
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        tiles.add(TileCoordinate(z: zoom, x: x, y: y));
      }
    }
    
    return tiles;
  }

  /// Convert lat/lng to tile coordinates at specific zoom
  static TileCoordinate _latLngToTile(LatLng latLng, int zoom) {
    final n = math.pow(2, zoom).toDouble();
    final xTile = ((latLng.longitude + 180) / 360 * n).floor();
    final latRad = latLng.latitude * math.pi / 180;
    final yTile = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n).floor();
    
    return TileCoordinate(z: zoom, x: xTile, y: yTile);
  }

  /// Update progress
  void _updateProgress(double progress, String status) {
    _currentStatus = status;
    _onProgress?.call(progress, status);
  }

  /// Cancel current download
  void cancelDownload() {
    if (_isDownloading) {
      debugPrint('🛑 Cancelling download...');
      _isCancelled = true;
    }
  }

  /// Clean up
  void dispose() {
    cancelDownload();
  }
}

/// Tile coordinate model
class TileCoordinate {
  final int z;
  final int x;
  final int y;

  TileCoordinate({
    required this.z,
    required this.x,
    required this.y,
  });

  @override
  String toString() => 'Tile(z=$z, x=$x, y=$y)';
}
