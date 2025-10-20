import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:hive/hive.dart';
import '../screens/basemap/cache_management_screen.dart';

/// Helper class to store file information
class FileInfo {
  final String path;
  final int size;
  final DateTime modified;
  
  FileInfo({
    required this.path,
    required this.size,
    required this.modified,
  });
}

class TileCacheService {
  // Generate unique box name for each basemap
  static String getHiveBoxName(String basemapId) => 'MapTileCache_$basemapId';
  
  /// Get TMS cache directory (Hive storage)
  Future<String> _getTmsCacheDirectory() async {
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}${Platform.pathSeparator}MapTiles';
  }

  /// Get PDF basemap tiles directory
  Future<String> _getPdfCacheDirectory(String basemapId) async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/pdf_tiles/$basemapId';
  }

  /// Get cache info for a basemap
  /// For TMS: reads from Hive database
  /// For PDF: reads from file system
  Future<CacheInfo> getCacheInfo(String basemapId, {bool isPdfBasemap = false}) async {
    if (isPdfBasemap) {
      return _getPdfCacheInfo(basemapId);
    } else {
      return _getTmsCacheInfo(basemapId);
    }
  }

  /// Get TMS cache info from Hive database for specific basemap
  Future<CacheInfo> _getTmsCacheInfo(String basemapId) async {
    try {
      final cacheDir = await _getTmsCacheDirectory();
      final boxName = getHiveBoxName(basemapId);
      
      print('\n--- Getting cache info for: $basemapId ---');
      print('Looking for box: $boxName');
      print('Cache directory: $cacheDir');
      
      // Scan all Hive files in directory
      final hiveFiles = await _scanHiveFiles();
      print('Found ${hiveFiles.length} Hive boxes in cache directory');
      
      for (var entry in hiveFiles.entries) {
        print('  - ${entry.key}: ${_formatBytes(entry.value.size)}');
      }
      
      int totalSize = 0;
      int fileCount = 0;
      DateTime? lastModified;
      
      // Try to find exact match first
      if (hiveFiles.containsKey(boxName)) {
        print('✓ Found exact match: $boxName');
        final fileInfo = hiveFiles[boxName]!;
        totalSize = fileInfo.size;
        lastModified = fileInfo.modified;
        
        // Add lock file if exists
        final lockFile = File('$cacheDir/$boxName.lock');
        if (await lockFile.exists()) {
          final lockStat = await lockFile.stat();
          totalSize += lockStat.size;
          print('  + Lock file: ${_formatBytes(lockStat.size)}');
        }
        
        // Try to get actual count from box
        try {
          Box? box;
          bool shouldClose = false;
          
          if (Hive.isBoxOpen(boxName)) {
            print('  Box is already open, reading...');
            box = Hive.box(boxName);
          } else {
            print('  Opening box to read count...');
            try {
              box = await Hive.openBox(boxName, path: cacheDir);
              shouldClose = true;
            } catch (e) {
              print('  Error opening box: $e');
            }
          }
          
          if (box != null) {
            fileCount = box.length;
            print('  ✓ Tile count from box: $fileCount');
            
            if (shouldClose) {
              await box.close();
              print('  Box closed after reading');
            }
          }
        } catch (e) {
          print('  Error reading box content: $e');
          // Fallback to estimation
          fileCount = (totalSize / 20000).round();
          print('  Using estimated count: $fileCount');
        }
        
        if (fileCount == 0 && totalSize > 0) {
          // If we couldn't read the box, estimate
          fileCount = (totalSize / 20000).round();
          print('  Using size-based estimation: $fileCount tiles');
        }
      } else {
        // Try to find partial match (case: flutter_map_cache uses different naming)
        print('✗ Exact match not found');
        print('Searching for partial matches containing: $basemapId');
        
        for (var entry in hiveFiles.entries) {
          if (entry.key.contains(basemapId)) {
            print('  Found partial match: ${entry.key}');
            totalSize += entry.value.size;
            if (lastModified == null || entry.value.modified.isAfter(lastModified)) {
              lastModified = entry.value.modified;
            }
            
            // Try to read this box
            try {
              Box? box;
              bool shouldClose = false;
              
              if (Hive.isBoxOpen(entry.key)) {
                box = Hive.box(entry.key);
              } else {
                try {
                  box = await Hive.openBox(entry.key, path: cacheDir);
                  shouldClose = true;
                } catch (e) {
                  print('  Error opening box ${entry.key}: $e');
                }
              }
              
              if (box != null) {
                fileCount += box.length;
                if (shouldClose) await box.close();
              }
            } catch (e) {
              print('  Error reading box ${entry.key}: $e');
            }
          }
        }
        
        if (totalSize > 0 && fileCount == 0) {
          fileCount = (totalSize / 20000).round();
          print('  Using estimation for partial matches: $fileCount tiles');
        }
      }
      
      print('Final result: ${_formatBytes(totalSize)}, $fileCount tiles');
      print('---\n');

      return CacheInfo(
        sizeInBytes: totalSize,
        tileCount: fileCount,
        lastModified: lastModified,
        isShared: false,
      );
    } catch (e) {
      print('❌ Error getting TMS cache info for $basemapId: $e');
      return CacheInfo(
        sizeInBytes: 0,
        tileCount: 0,
        lastModified: null,
      );
    }
  }

  /// Debug method to list all files in cache directory
  Future<void> debugCacheDirectory() async {
    final cacheDir = await _getTmsCacheDirectory();
    final directory = Directory(cacheDir);
    
    print('\n=== DEBUG CACHE DIRECTORY ===');
    print('Cache Path: $cacheDir');
    print('Exists: ${await directory.exists()}');
    
    if (await directory.exists()) {
      print('\nFiles in cache directory:');
      int totalFiles = 0;
      int totalSize = 0;
      await for (var entity in directory.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          final fileName = entity.path.split(Platform.pathSeparator).last;
          print('$fileName - ${_formatBytes(stat.size)} (modified: ${stat.modified})');
          totalFiles++;
          totalSize += stat.size;
        }
      }
      print('\nTotal files: $totalFiles');
      print('Total size: ${_formatBytes(totalSize)}');
    } else {
      print('Directory does NOT exist!');
    }
    print('=========================\n');
  }

  /// Scan directory and find all Hive files
  Future<Map<String, FileInfo>> _scanHiveFiles() async {
    final cacheDir = await _getTmsCacheDirectory();
    final directory = Directory(cacheDir);
    final Map<String, FileInfo> files = {};
    
    if (!await directory.exists()) {
      return files;
    }
    
    await for (var entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.hive')) {
        final stat = await entity.stat();
        final fileName = entity.path.split(Platform.pathSeparator).last;
        final boxName = fileName.replaceAll('.hive', '');
        
        files[boxName] = FileInfo(
          path: entity.path,
          size: stat.size,
          modified: stat.modified,
        );
      }
    }
    
    return files;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Get PDF cache info from file system
  Future<CacheInfo> _getPdfCacheInfo(String basemapId) async {
    try {
      final cacheDir = await _getPdfCacheDirectory(basemapId);
      final directory = Directory(cacheDir);

      if (!await directory.exists()) {
        return CacheInfo(
          sizeInBytes: 0,
          tileCount: 0,
          lastModified: null,
        );
      }

      int totalSize = 0;
      int tileCount = 0;
      DateTime? lastModified;

      // Recursively count PNG files and calculate size
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
      print('Error getting PDF cache info for $basemapId: $e');
      return CacheInfo(
        sizeInBytes: 0,
        tileCount: 0,
        lastModified: null,
      );
    }
  }

  /// Clear TMS cache for specific basemap
  Future<void> clearTmsCache(String basemapId) async {
    try {
      print('\n=== Clearing TMS cache for: $basemapId ===');
      final cacheDir = await _getTmsCacheDirectory();
      final boxName = getHiveBoxName(basemapId);
      
      print('Box name: $boxName');
      print('Cache directory: $cacheDir');
      
      // First, scan to find actual files
      final hiveFiles = await _scanHiveFiles();
      List<String> filesToDelete = [];
      
      // Find files matching this basemap
      for (var entry in hiveFiles.entries) {
        if (entry.key == boxName || entry.key.contains(basemapId)) {
          filesToDelete.add(entry.key);
          print('Found cache file to delete: ${entry.key}');
        }
      }
      
      if (filesToDelete.isEmpty) {
        print('No cache files found for $basemapId');
        return;
      }
      
      // Close and clear each box
      for (var boxToDelete in filesToDelete) {
        print('Processing box: $boxToDelete');
        
        try {
          // Close box if open
          if (Hive.isBoxOpen(boxToDelete)) {
            print('  Box is open, closing...');
            final box = Hive.box(boxToDelete);
            await box.clear();
            await box.close();
            print('  ✓ Box closed and cleared');
          } else {
            print('  Box is not open');
          }
        } catch (e) {
          print('  Error closing box: $e');
        }
        
        // Delete the .hive file
        final hiveFile = File('$cacheDir/$boxToDelete.hive');
        if (await hiveFile.exists()) {
          try {
            await hiveFile.delete();
            print('  ✓ Deleted: $boxToDelete.hive');
          } catch (e) {
            print('  ✗ Error deleting .hive file: $e');
          }
        } else {
          print('  .hive file does not exist');
        }
        
        // Delete the .lock file
        final lockFile = File('$cacheDir/$boxToDelete.lock');
        if (await lockFile.exists()) {
          try {
            await lockFile.delete();
            print('  ✓ Deleted: $boxToDelete.lock');
          } catch (e) {
            print('  ✗ Error deleting .lock file: $e');
          }
        } else {
          print('  .lock file does not exist');
        }
      }
      
      print('✓ TMS cache cleared for $basemapId');
      print('=================================\n');
    } catch (e) {
      print('❌ Error clearing TMS cache for $basemapId: $e');
      rethrow;
    }
  }

  /// Clear cache for specific basemap
  Future<void> clearCache(String basemapId, {bool isPdfBasemap = false}) async {
    if (isPdfBasemap) {
      // Don't allow clearing PDF cache
      throw Exception('PDF basemap cache cannot be cleared from here');
    } else {
      // Clear TMS cache for this specific basemap
      await clearTmsCache(basemapId);
    }
  }

  /// Clear all TMS cache (for all basemaps)
  Future<void> clearAllTmsCache() async {
    try {
      print('\n=== Clearing ALL TMS cache ===');
      final cacheDir = await _getTmsCacheDirectory();
      final directory = Directory(cacheDir);
      
      if (!await directory.exists()) {
        print('Cache directory does not exist');
        return;
      }
      
      // Scan all Hive files
      final hiveFiles = await _scanHiveFiles();
      print('Found ${hiveFiles.length} Hive boxes to clear');
      
      if (hiveFiles.isEmpty) {
        print('No cache files to clear');
        return;
      }
      
      int deletedCount = 0;
      int errorCount = 0;
      
      // Process each box
      for (var entry in hiveFiles.entries) {
        final boxName = entry.key;
        
        // Only delete MapTileCache boxes
        if (!boxName.startsWith('MapTileCache_')) {
          print('Skipping non-cache box: $boxName');
          continue;
        }
        
        print('\nProcessing: $boxName');
        
        try {
          // Close box if open
          if (Hive.isBoxOpen(boxName)) {
            print('  Box is open, closing...');
            try {
              final box = Hive.box(boxName);
              await box.clear();
              await box.close();
              print('  ✓ Box closed and cleared');
            } catch (e) {
              print('  ✗ Error closing box: $e');
            }
          }
          
          // Delete .hive file
          final hiveFile = File('$cacheDir/$boxName.hive');
          if (await hiveFile.exists()) {
            try {
              await hiveFile.delete();
              print('  ✓ Deleted: $boxName.hive');
              deletedCount++;
            } catch (e) {
              print('  ✗ Error deleting .hive: $e');
              errorCount++;
            }
          }
          
          // Delete .lock file
          final lockFile = File('$cacheDir/$boxName.lock');
          if (await lockFile.exists()) {
            try {
              await lockFile.delete();
              print('  ✓ Deleted: $boxName.lock');
            } catch (e) {
              print('  ✗ Error deleting .lock: $e');
            }
          }
        } catch (e) {
          print('  ❌ Error processing $boxName: $e');
          errorCount++;
        }
      }
      
      print('\n=== Clear All Summary ===');
      print('Successfully deleted: $deletedCount files');
      print('Errors: $errorCount');
      print('✓ All TMS cache cleared');
      print('========================\n');
    } catch (e) {
      print('❌ Error clearing all TMS cache: $e');
      rethrow;
    }
  }

  /// Get total TMS cache size (all basemaps)
  Future<int> getTotalTmsCacheSize() async {
    try {
      final cacheDir = await _getTmsCacheDirectory();
      final directory = Directory(cacheDir);

      if (!await directory.exists()) {
        return 0;
      }

      int totalSize = 0;

      await for (var entity in directory.list()) {
        if (entity is File && 
            (entity.path.endsWith('.hive') || entity.path.endsWith('.lock'))) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }

      return totalSize;
    } catch (e) {
      print('Error getting total TMS cache size: $e');
      return 0;
    }
  }

  /// Get all cache info (combined TMS and PDF)
  Future<Map<String, CacheInfo>> getAllCacheInfo(List<String> basemapIds, List<bool> isPdfFlags) async {
    final Map<String, CacheInfo> cacheMap = {};

    for (int i = 0; i < basemapIds.length; i++) {
      final basemapId = basemapIds[i];
      final isPdf = isPdfFlags[i];
      
      try {
        final info = await getCacheInfo(basemapId, isPdfBasemap: isPdf);
        cacheMap[basemapId] = info;
      } catch (e) {
        print('Error getting cache info for $basemapId: $e');
        cacheMap[basemapId] = CacheInfo(
          sizeInBytes: 0,
          tileCount: 0,
          lastModified: null,
        );
      }
    }

    return cacheMap;
  }

  /// Check if TMS cache exists for any basemap
  Future<bool> hasTmsCache() async {
    try {
      final cacheDir = await _getTmsCacheDirectory();
      final directory = Directory(cacheDir);
      
      if (!await directory.exists()) {
        return false;
      }
      
      // Check if there are any Hive files
      await for (var entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.hive')) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if TMS cache exists for specific basemap
  Future<bool> hasTmsCacheForBasemap(String basemapId) async {
    try {
      final cacheDir = await _getTmsCacheDirectory();
      final boxName = getHiveBoxName(basemapId);
      final hiveFile = File('$cacheDir/$boxName.hive');
      return await hiveFile.exists();
    } catch (e) {
      return false;
    }
  }

  /// Check if PDF cache exists for a basemap
  Future<bool> hasPdfCache(String basemapId) async {
    try {
      final cacheDir = await _getPdfCacheDirectory(basemapId);
      final directory = Directory(cacheDir);
      return await directory.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get TMS cache path
  Future<String> getTmsCachePath() async {
    return await _getTmsCacheDirectory();
  }

  /// Get PDF cache path
  Future<String> getPdfCachePath(String basemapId) async {
    return await _getPdfCacheDirectory(basemapId);
  }
}
