import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../screens/basemap/cache_management_screen.dart';

import '../utils/app_logger.dart';
/// SQLite-based Tile Cache Service - JAUH LEBIH CEPAT dari Hive!
/// Performance: 10-50x lebih cepat untuk operasi read/write tile
class TileCacheSqliteService {
  static Database? _database;
  static final Map<String, Database?> _databaseCache = {};
  static const int _maxOpenDatabases = 5; // Limit untuk mobile devices

  /// Get database instance for specific basemap (connection pooling)
  Future<Database> _getDatabase(String basemapId) async {
    // Return cached database if exists and is open
    if (_databaseCache.containsKey(basemapId) && _databaseCache[basemapId] != null) {
      final db = _databaseCache[basemapId]!;
      if (db.isOpen) {
        return db;
      } else {
        // Database was closed, remove from cache
        _databaseCache.remove(basemapId);
      }
    }

    // Enforce max open databases limit
    if (_databaseCache.length >= _maxOpenDatabases) {
      // Close least recently used database
      final oldestKey = _databaseCache.keys.first;
      final oldestDb = _databaseCache[oldestKey];
      if (oldestDb != null && oldestDb.isOpen) {
        await oldestDb.close();
        logDebug('🔒 Closed database $oldestKey to maintain connection limit', tag: 'TILE');
      }
      _databaseCache.remove(oldestKey);
    }

    final directory = await getApplicationSupportDirectory();
    final dbPath = path.join(directory.path, 'MapTiles', 'tiles_$basemapId.db');
    
    // Ensure directory exists
    final dbDir = Directory(path.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
      logDebug('✓ Created cache directory: ${dbDir.path}', tag: 'TILE');
    }

    // Open database with optimizations
    final database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        // Create table with optimized schema
        await db.execute('''
          CREATE TABLE tiles (
            tile_key TEXT PRIMARY KEY,
            tile_data BLOB NOT NULL,
            cached_at INTEGER NOT NULL,
            last_accessed INTEGER NOT NULL
          )
        ''');
        
        // Create indexes for fast lookups
        await db.execute('CREATE INDEX idx_cached_at ON tiles(cached_at)');
        await db.execute('CREATE INDEX idx_last_accessed ON tiles(last_accessed)');
      },
    );

    // Enable optimizations AFTER database is opened (not in onOpen callback)
    try {
      await database.rawQuery('PRAGMA journal_mode=WAL');
      await database.rawQuery('PRAGMA synchronous=NORMAL');
      await database.rawQuery('PRAGMA cache_size=10000');
      await database.rawQuery('PRAGMA temp_store=MEMORY');
      logDebug('✓ Database optimizations enabled for $basemapId', tag: 'TILE');
    } catch (e) {
      logWarn('⚠️ Warning: Could not enable all optimizations: $e', tag: 'TILE');
      // Continue anyway - database will still work
    }

    _databaseCache[basemapId] = database;
    return database;
  }

  /// Generate tile key from coordinates
  String _getTileKey(int z, int x, int y) {
    return '${z}_${x}_$y';
  }

  /// Save tile to cache - SANGAT CEPAT!
  Future<void> saveTile({
    required String basemapId,
    required int z,
    required int x,
    required int y,
    required Uint8List tileData,
  }) async {
    try {
      final db = await _getDatabase(basemapId);
      final tileKey = _getTileKey(z, x, y);
      final now = DateTime.now().millisecondsSinceEpoch;

      // Use rawInsert for better performance and compatibility
      await db.rawInsert(
        'INSERT OR REPLACE INTO tiles (tile_key, tile_data, cached_at, last_accessed) VALUES (?, ?, ?, ?)',
        [tileKey, tileData, now, now],
      );
      
      // Only log first few tiles to avoid spam
      if (tileKey.split('_')[0] == '13' && int.parse(tileKey.split('_')[1]) <= 1) {
        logDebug('💾 Tile saved: $basemapId/$tileKey (${tileData.length} bytes)', tag: 'TILE');
      }
    } catch (e) {
      logDebug('❌ Error saving tile $basemapId z=$z,x=$x,y=$y: $e', tag: 'TILE');
      // Don't rethrow - we want to continue even if save fails
    }
  }

  /// Get tile from cache - SUPER CEPAT!
  Future<Uint8List?> getTile({
    required String basemapId,
    required int z,
    required int x,
    required int y,
  }) async {
    try {
      final db = await _getDatabase(basemapId);
      final tileKey = _getTileKey(z, x, y);

      // Use rawQuery for better compatibility
      final List<Map<String, dynamic>> maps = await db.rawQuery(
        'SELECT tile_data FROM tiles WHERE tile_key = ? LIMIT 1',
        [tileKey],
      );

      if (maps.isNotEmpty) {
        final data = maps.first['tile_data'] as Uint8List;
        // Reduce log spam - only log occasionally
        // print('✅ Cache HIT: $basemapId/$tileKey (${data.length} bytes)');
        // Update last accessed time asynchronously (don't wait)
        _updateLastAccessed(db, tileKey);
        return data;
      }

      // Reduce log spam for cache misses
      // print('⚠️ Cache MISS: $basemapId/$tileKey');
      return null;
    } catch (e) {
      logDebug('❌ Error getting tile $basemapId/$z/$x/$y: $e', tag: 'TILE');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PARENT TILE FALLBACK
  // ─────────────────────────────────────────────────────────────────────────

  /// Walk up the zoom pyramid looking for a cached parent tile.
  ///
  /// For tile (z, x, y), the parent at zoom delta [dz] is:
  ///   parent_z = z - dz
  ///   parent_x = x >> dz
  ///   parent_y = y >> dz
  ///
  /// Returns the first hit found (lowest dz = sharpest result), or null.
  Future<ParentTileResult?> getParentTile({
    required String basemapId,
    required int z,
    required int x,
    required int y,
    int maxDelta = 3,
  }) async {
    for (int dz = 1; dz <= maxDelta; dz++) {
      final pz = z - dz;
      if (pz < 0) break;
      final data = await getTile(
        basemapId: basemapId,
        z: pz,
        x: x >> dz,
        y: y >> dz,
      );
      if (data != null) {
        return ParentTileResult(data: data, zoomDelta: dz);
      }
    }
    return null;
  }

  /// Update last accessed time (fire and forget)
  void _updateLastAccessed(Database db, String tileKey) {
    // Use rawUpdate for better compatibility
    db.rawUpdate(
      'UPDATE tiles SET last_accessed = ? WHERE tile_key = ?',
      [DateTime.now().millisecondsSinceEpoch, tileKey],
    ).catchError((e) {
      // Ignore errors - this is just for statistics
      return 0; // catchError pada Future<int> wajib mengembalikan int
    });
  }

  /// Get cache info for basemap
  Future<CacheInfo> getCacheInfo(String basemapId, {bool isPdfBasemap = false}) async {
    if (isPdfBasemap) {
      return _getPdfCacheInfo(basemapId);
    }

    try {
      final db = await _getDatabase(basemapId);

      // Get count and total size
      final countResult = await db.rawQuery('SELECT COUNT(*) as count, SUM(LENGTH(tile_data)) as size FROM tiles');
      
      final count = countResult.first['count'] as int? ?? 0;
      final size = countResult.first['size'] as int? ?? 0;

      // Get last modified date
      DateTime? lastModified;
      if (count > 0) {
        final lastModResult = await db.rawQuery('SELECT MAX(cached_at) as last_modified FROM tiles');
        final lastModTs = lastModResult.first['last_modified'] as int?;
        if (lastModTs != null) {
          lastModified = DateTime.fromMillisecondsSinceEpoch(lastModTs);
        }
      }

      return CacheInfo(
        sizeInBytes: size,
        tileCount: count,
        lastModified: lastModified,
        isShared: false,
      );
    } catch (e) {
      logWarn('Error getting cache info: $e', tag: 'TILE');
      return CacheInfo(
        sizeInBytes: 0,
        tileCount: 0,
        lastModified: null,
      );
    }
  }

  /// Get PDF cache info
  Future<CacheInfo> _getPdfCacheInfo(String basemapId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = '${appDir.path}/pdf_tiles/$basemapId';
      final directory = Directory(cacheDir);

      if (!await directory.exists()) {
        return CacheInfo(sizeInBytes: 0, tileCount: 0, lastModified: null);
      }

      int totalSize = 0;
      int tileCount = 0;
      DateTime? lastModified;

      await for (var entity in directory.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.png')) {
          final stat = await entity.stat();
          totalSize += stat.size;
          tileCount++;
          
          if (lastModified == null || stat.modified.isAfter(lastModified)) {
            lastModified = stat.modified;
          }
        }
      }

      return CacheInfo(
        sizeInBytes: totalSize,
        tileCount: tileCount,
        lastModified: lastModified,
      );
    } catch (e) {
      logWarn('Error getting PDF cache info: $e', tag: 'TILE');
      return CacheInfo(sizeInBytes: 0, tileCount: 0, lastModified: null);
    }
  }

  /// Clear cache for specific basemap
  Future<void> clearCache(String basemapId, {bool isPdfBasemap = false}) async {
    if (isPdfBasemap) {
      throw Exception('PDF basemap cache cannot be cleared from here');
    }

    try {
      final db = await _getDatabase(basemapId);
      await db.rawDelete('DELETE FROM tiles');
      
      logDebug('✓ Cache cleared for $basemapId', tag: 'TILE');
    } catch (e) {
      logWarn('Error clearing cache: $e', tag: 'TILE');
      rethrow;
    }
  }

  /// Clear all TMS cache
  Future<void> clearAllTmsCache() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final tilesDir = Directory(path.join(directory.path, 'MapTiles'));
      
      if (!await tilesDir.exists()) {
        return;
      }

      // Close all database connections
      for (var db in _databaseCache.values) {
        await db?.close();
      }
      _databaseCache.clear();

      // Delete all database files
      await for (var entity in tilesDir.list()) {
        if (entity is File && entity.path.endsWith('.db')) {
          await entity.delete();
          logDebug('Deleted: ${path.basename(entity.path)}', tag: 'TILE');
        }
      }

      logDebug('✓ All TMS cache cleared', tag: 'TILE');
    } catch (e) {
      logWarn('Error clearing all cache: $e', tag: 'TILE');
      rethrow;
    }
  }

  /// Get total TMS cache size
  Future<int> getTotalTmsCacheSize() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final tilesDir = Directory(path.join(directory.path, 'MapTiles'));
      
      if (!await tilesDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (var entity in tilesDir.list()) {
        if (entity is File && entity.path.endsWith('.db')) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }

      return totalSize;
    } catch (e) {
      logWarn('Error getting total cache size: $e', tag: 'TILE');
      return 0;
    }
  }

  /// Check if cache exists for basemap
  Future<bool> hasCacheForBasemap(String basemapId) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final dbPath = path.join(directory.path, 'MapTiles', 'tiles_$basemapId.db');
      return await File(dbPath).exists();
    } catch (e) {
      return false;
    }
  }

  /// Get cache path
  Future<String> getCachePath() async {
    final directory = await getApplicationSupportDirectory();
    return path.join(directory.path, 'MapTiles');
  }

  /// Close all database connections (call on app dispose)
  Future<void> closeAll() async {
    for (var db in _databaseCache.values) {
      await db?.close();
    }
    _databaseCache.clear();
  }

  /// Clean old tiles (older than maxAge)
  Future<void> cleanOldTiles(String basemapId, Duration maxAge) async {
    try {
      final db = await _getDatabase(basemapId);
      final cutoffTime = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
      
      final deleted = await db.rawDelete(
        'DELETE FROM tiles WHERE last_accessed < ?',
        [cutoffTime],
      );
      
      logDebug('Cleaned $deleted old tiles from $basemapId', tag: 'TILE');
    } catch (e) {
      logWarn('Error cleaning old tiles: $e', tag: 'TILE');
    }
  }

  /// Debug cache directory (print all cache files)
  // ignore: unused_element
  Future<void> debugCacheDirectory() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final tilesDir = Directory(path.join(directory.path, 'MapTiles'));
      
      logDebug('\n========== SQLITE CACHE DEBUG ==========', tag: 'TILE');
      logDebug('Cache directory: ${tilesDir.path}', tag: 'TILE');
      logDebug('Directory exists: ${await tilesDir.exists()}', tag: 'TILE');
      
      if (!await tilesDir.exists()) {
        logDebug('Cache directory does not exist yet.', tag: 'TILE');
        logDebug('========================================\n', tag: 'TILE');
        return;
      }
      
      logDebug('\nDatabase files:', tag: 'TILE');
      int totalSize = 0;
      int fileCount = 0;
      
      await for (var entity in tilesDir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          final fileName = path.basename(entity.path);
          final sizeKb = (stat.size / 1024).toStringAsFixed(2);
          logDebug('  - $fileName: $sizeKb KB', tag: 'TILE');
          totalSize += stat.size;
          fileCount++;
        }
      }
      
      logDebug('\nTotal: $fileCount files, ${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB', tag: 'TILE');
      logDebug('========================================\n', tag: 'TILE');
    } catch (e) {
      logWarn('Error debugging cache: $e', tag: 'TILE');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASSES
// ─────────────────────────────────────────────────────────────────────────────

/// Result of a parent-tile lookup.
/// [data] is the raw PNG bytes of the parent tile.
/// [zoomDelta] is how many zoom levels up it was found (1 = sharpest).
class ParentTileResult {
  final Uint8List data;
  final int zoomDelta;
  const ParentTileResult({required this.data, required this.zoomDelta});
}
