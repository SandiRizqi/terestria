import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Manager untuk mengelola concurrent tile downloads dengan priority queue
/// dan retry mechanism
class TileDownloadManager {
  static final TileDownloadManager _instance = TileDownloadManager._internal();
  factory TileDownloadManager() => _instance;
  TileDownloadManager._internal();

  // Shared HTTP client dengan connection pool
  static final http.Client _httpClient = http.Client();
  
  // Configuration
  static const int _maxConcurrentDownloads = 6;
  static const Duration _downloadTimeout = Duration(seconds: 15);
  static const int _maxRetries = 2;
  static const Duration _retryDelay = Duration(milliseconds: 500);
  
  // State
  int _activeDownloads = 0;
  final List<_TileDownloadTask> _queue = [];
  final Map<String, Completer<Uint8List?>> _pendingDownloads = {};
  
  // Statistics
  int _successCount = 0;
  int _failCount = 0;
  int _retryCount = 0;
  
  /// Download tile dengan priority queue dan retry mechanism
  Future<Uint8List?> downloadTile({
    required String url,
    required int z,
    required int x,
    required int y,
    bool isVisible = true,
  }) async {
    final taskKey = '$z/$x/$y';
    
    // Check if already downloading this tile
    if (_pendingDownloads.containsKey(taskKey)) {
      return _pendingDownloads[taskKey]!.future;
    }
    
    // Create completer for this download
    final completer = Completer<Uint8List?>();
    _pendingDownloads[taskKey] = completer;
    
    // Create download task
    final task = _TileDownloadTask(
      url: url,
      z: z,
      x: x,
      y: y,
      isVisible: isVisible,
      completer: completer,
      retryCount: 0,
    );
    
    // Add to queue based on priority
    if (isVisible) {
      // Visible tiles have higher priority - add to front
      _queue.insert(0, task);
    } else {
      // Non-visible tiles - add to back
      _queue.add(task);
    }
    
    // Start processing queue
    _processQueue();
    
    return completer.future;
  }
  
  /// Process download queue
  void _processQueue() {
    // Process tasks while we have capacity and tasks in queue
    while (_activeDownloads < _maxConcurrentDownloads && _queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      _activeDownloads++;
      
      _downloadTask(task).then((_) {
        _activeDownloads--;
        _processQueue(); // Process next task
      });
    }
  }
  
  /// Download a single task with retry logic
  Future<void> _downloadTask(_TileDownloadTask task) async {
    final taskKey = '${task.z}/${task.x}/${task.y}';
    
    try {
      // Attempt download with timeout
      final response = await _httpClient.get(
        Uri.parse(task.url),
        headers: {
          'User-Agent': 'GeoformApp/1.0',
        },
      ).timeout(_downloadTimeout);
      
      if (response.statusCode == 200) {
        final bytes = Uint8List.fromList(response.bodyBytes);
        
        // Success!
        _successCount++;
        if (task.retryCount > 0) {
          print('✅ Tile z=${task.z}, x=${task.x}, y=${task.y} downloaded after ${task.retryCount} retries (${bytes.length} bytes)');
        }
        
        task.completer.complete(bytes);
        _pendingDownloads.remove(taskKey);
      } else if (response.statusCode == 429) {
        // Rate limited - retry with longer delay
        throw _RateLimitException('Rate limited (HTTP 429)');
      } else if (response.statusCode >= 500) {
        // Server error - worth retrying
        throw _ServerException('Server error (HTTP ${response.statusCode})');
      } else {
        // Client error - don't retry
        throw _ClientException('Client error (HTTP ${response.statusCode})');
      }
    } on TimeoutException catch (e) {
      await _handleDownloadError(task, taskKey, 'Timeout', e, canRetry: true);
    } on _RateLimitException catch (e) {
      await _handleDownloadError(task, taskKey, 'Rate limited', e, canRetry: true, retryDelay: const Duration(seconds: 2));
    } on _ServerException catch (e) {
      await _handleDownloadError(task, taskKey, 'Server error', e, canRetry: true);
    } on _ClientException catch (e) {
      await _handleDownloadError(task, taskKey, 'Client error', e, canRetry: false);
    } catch (e) {
      await _handleDownloadError(task, taskKey, 'Network error', e, canRetry: true);
    }
  }
  
  /// Handle download error with retry logic
  Future<void> _handleDownloadError(
    _TileDownloadTask task,
    String taskKey,
    String errorType,
    dynamic error,
    {required bool canRetry, Duration? retryDelay}
  ) async {
    if (canRetry && task.retryCount < _maxRetries) {
      // Retry with exponential backoff
      _retryCount++;
      task.retryCount++;
      
      final delay = retryDelay ?? Duration(milliseconds: _retryDelay.inMilliseconds * task.retryCount);
      
      print('⚠️ $errorType for tile z=${task.z}, x=${task.x}, y=${task.y} - Retry ${task.retryCount}/$_maxRetries in ${delay.inMilliseconds}ms');
      
      await Future.delayed(delay);
      
      // Re-add to queue for retry
      if (task.isVisible) {
        _queue.insert(0, task);
      } else {
        _queue.add(task);
      }
    } else {
      // Max retries reached or not retriable
      _failCount++;
      
      if (task.retryCount >= _maxRetries) {
        print('❌ Download failed for tile z=${task.z}, x=${task.x}, y=${task.y} after ${task.retryCount} retries: $errorType');
      } else {
        print('❌ Download failed for tile z=${task.z}, x=${task.x}, y=${task.y}: $errorType (not retriable)');
      }
      
      task.completer.complete(null);
      _pendingDownloads.remove(taskKey);
    }
  }
  
  /// Cancel pending downloads for specific tiles (useful when tiles are no longer visible)
  void cancelPendingDownloads(List<String> taskKeys) {
    for (final key in taskKeys) {
      final completer = _pendingDownloads[key];
      if (completer != null && !completer.isCompleted) {
        completer.complete(null);
        _pendingDownloads.remove(key);
      }
    }
    
    // Remove from queue
    _queue.removeWhere((task) {
      final taskKey = '${task.z}/${task.x}/${task.y}';
      return taskKeys.contains(taskKey);
    });
  }
  
  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'activeDownloads': _activeDownloads,
      'queuedDownloads': _queue.length,
      'pendingDownloads': _pendingDownloads.length,
      'successCount': _successCount,
      'failCount': _failCount,
      'retryCount': _retryCount,
      'successRate': _successCount + _failCount > 0 
          ? (_successCount / (_successCount + _failCount) * 100).toStringAsFixed(1) + '%'
          : 'N/A',
    };
  }
  
  /// Reset statistics
  void resetStatistics() {
    _successCount = 0;
    _failCount = 0;
    _retryCount = 0;
  }
  
  /// Clear all pending downloads and queue
  void clearAll() {
    _queue.clear();
    for (final completer in _pendingDownloads.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _pendingDownloads.clear();
  }
  
  /// Dispose (close HTTP client)
  void dispose() {
    clearAll();
    _httpClient.close();
  }
}

/// Internal download task model
class _TileDownloadTask {
  final String url;
  final int z;
  final int x;
  final int y;
  final bool isVisible;
  final Completer<Uint8List?> completer;
  int retryCount;
  
  _TileDownloadTask({
    required this.url,
    required this.z,
    required this.x,
    required this.y,
    required this.isVisible,
    required this.completer,
    required this.retryCount,
  });
}

/// Custom exceptions for better error handling
class _RateLimitException implements Exception {
  final String message;
  _RateLimitException(this.message);
  @override
  String toString() => message;
}

class _ServerException implements Exception {
  final String message;
  _ServerException(this.message);
  @override
  String toString() => message;
}

class _ClientException implements Exception {
  final String message;
  _ClientException(this.message);
  @override
  String toString() => message;
}
