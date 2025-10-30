import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/basemap_model.dart';
import '../../services/basemap_service.dart';
import '../../services/tile_cache_sqlite_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';

class CacheManagementScreen extends StatefulWidget {
  const CacheManagementScreen({Key? key}) : super(key: key);

  @override
  State<CacheManagementScreen> createState() => _CacheManagementScreenState();
}

class _CacheManagementScreenState extends State<CacheManagementScreen> {
  final BasemapService _basemapService = BasemapService();
  final TileCacheSqliteService _cacheService = TileCacheSqliteService();
  
  List<Basemap> _basemaps = [];
  Map<String, CacheInfo> _cacheInfoMap = {};
  bool _isLoading = true;
  bool _isRefreshing = false;
  int _totalCacheSize = 0;
  int _totalTileCount = 0;

  @override
  void initState() {
    super.initState();
    _debugCache(); // Debug first to see what files exist
    _loadCacheData();
  }
  
  Future<void> _debugCache() async {
    await _cacheService.debugCacheDirectory();
  }

  Future<void> _loadCacheData() async {
    setState(() => _isLoading = true);
    
    try {
      final basemaps = await _basemapService.getBasemaps();
      final Map<String, CacheInfo> cacheMap = {};
      int totalSize = 0;
      int totalTiles = 0;
      
      print('Loading cache data for ${basemaps.length} basemaps...');
      
      for (var basemap in basemaps) {
        final info = await _getCacheInfo(basemap);
        cacheMap[basemap.id] = info;
        totalSize += info.sizeInBytes;
        totalTiles += info.tileCount;
        print('${basemap.name}: ${_formatSize(info.sizeInBytes)}, ${info.tileCount} tiles');
      }
      
      print('Total cache: ${_formatSize(totalSize)}, $totalTiles tiles');
      
      if (mounted) {
        setState(() {
          _basemaps = basemaps;
          _cacheInfoMap = cacheMap;
          _totalCacheSize = totalSize;
          _totalTileCount = totalTiles;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading cache data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Failed to load cache data: $e');
      }
    }
  }

  Future<CacheInfo> _getCacheInfo(Basemap basemap) async {
    try {
      return await _cacheService.getCacheInfo(
        basemap.id,
        isPdfBasemap: basemap.isPdfBasemap,
      );
    } catch (e) {
      print('Error getting cache info for ${basemap.name}: $e');
      return CacheInfo(
        sizeInBytes: 0,
        tileCount: 0,
        lastModified: null,
        isShared: false,
      );
    }
  }

  Future<void> _refreshCache() async {
    setState(() => _isRefreshing = true);
    await _loadCacheData();
    setState(() => _isRefreshing = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Cache data refreshed'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _clearCache(Basemap basemap) async {
    if (basemap.isPdfBasemap) {
      _showError(
        'PDF basemap cache cannot be cleared here.\n'
        'Delete the basemap from Basemap Management to remove all data.',
      );
      return;
    }

    final cacheInfo = _cacheInfoMap[basemap.id];
    if (cacheInfo == null || cacheInfo.sizeInBytes == 0) {
      _showError('No cache to clear for ${basemap.name}');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: Text(
          'Clear cached tiles for "${basemap.name}"?\n\n'
          'This will free up ${_formatSize(cacheInfo.sizeInBytes)} '
          'of storage. Tiles will be re-downloaded when needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _showLoadingDialog('Clearing cache...');
      
      try {
        await _cacheService.clearCache(basemap.id, isPdfBasemap: false);
        
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          
          // Wait a bit for file system to update
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Reload cache data
          await _loadCacheData();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Cache cleared for ${basemap.name}'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          _showError('Failed to clear cache: $e');
        }
      }
    }
  }

  Future<void> _clearAllCache() async {
    final tmsBasemaps = _basemaps.where((b) => !b.isPdfBasemap).toList();
    
    if (tmsBasemaps.isEmpty) {
      _showError('No TMS basemap cache to clear');
      return;
    }

    final tmsCacheSize = tmsBasemaps.fold<int>(
      0, 
      (sum, b) => sum + (_cacheInfoMap[b.id]?.sizeInBytes ?? 0),
    );

    if (tmsCacheSize == 0) {
      _showError('No TMS cache to clear');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 12),
            Text('Clear All TMS Cache'),
          ],
        ),
        content: Text(
          'Clear all cached tiles for all TMS basemaps?\n\n'
          'This will free up ${_formatSize(tmsCacheSize)} of storage.\n\n'
          'Note: PDF basemap caches are not affected and must be deleted '
          'individually from Basemap Management.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _showLoadingDialog('Clearing all TMS cache...');
      
      try {
        await _cacheService.clearAllTmsCache();
        
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          
          // Wait a bit for file system to update
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Reload cache data
          await _loadCacheData();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('All TMS cache cleared successfully'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          _showError('Failed to clear cache: $e');
        }
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: AppTheme.errorColor),
            SizedBox(width: 12),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cache Management'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () async {
              await _cacheService.debugCacheDirectory();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Debug info printed to console'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Debug Cache',
          ),
          IconButton(
            icon: _isRefreshing 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshCache,
            tooltip: 'Refresh',
          ),
          const ConnectivityIndicator(showLabel: false, iconSize: 24),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryCard(),
                Expanded(child: _buildCacheList()),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    final tmsCacheSize = _basemaps
        .where((b) => !b.isPdfBasemap)
        .fold<int>(0, (sum, b) => sum + (_cacheInfoMap[b.id]?.sizeInBytes ?? 0));
    
    final pdfCacheSize = _basemaps
        .where((b) => b.isPdfBasemap)
        .fold<int>(0, (sum, b) => sum + (_cacheInfoMap[b.id]?.sizeInBytes ?? 0));

    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.storage,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Cache Storage',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatSize(_totalCacheSize),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 1,
                color: Colors.white.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.map,
                      label: 'TMS Cache',
                      value: _formatSize(tmsCacheSize),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.picture_as_pdf,
                      label: 'PDF Cache',
                      value: _formatSize(pdfCacheSize),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.grid_on,
                      label: 'Total Tiles',
                      value: _totalTileCount.toString(),
                    ),
                  ),
                ],
              ),
              if (tmsCacheSize > 0) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _clearAllCache,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Clear All TMS Cache'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCacheList() {
    if (_basemaps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.storage_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Basemaps Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add basemaps to see cache information',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _basemaps.length,
      itemBuilder: (context, index) {
        final basemap = _basemaps[index];
        final cacheInfo = _cacheInfoMap[basemap.id];
        
        return _buildCacheItem(basemap, cacheInfo);
      },
    );
  }

  Widget _buildCacheItem(Basemap basemap, CacheInfo? cacheInfo) {
    final sizeInBytes = cacheInfo?.sizeInBytes ?? 0;
    final tileCount = cacheInfo?.tileCount ?? 0;
    final isPdf = basemap.isPdfBasemap;
    final hasCache = sizeInBytes > 0;
    
    Color typeColor;
    IconData typeIcon;
    String typeLabel;
    
    if (basemap.type == BasemapType.builtin) {
      typeColor = Colors.blue;
      typeIcon = Icons.public;
      typeLabel = 'BUILTIN';
    } else if (isPdf) {
      typeColor = Colors.purple;
      typeIcon = Icons.picture_as_pdf;
      typeLabel = 'PDF';
    } else {
      typeColor = Colors.green;
      typeIcon = Icons.map;
      typeLabel = 'TMS';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        basemap.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: typeColor.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: typeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Show delete button if: NOT PDF and HAS cache
                if (!isPdf && hasCache)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: AppTheme.errorColor,
                    onPressed: () => _clearCache(basemap),
                    tooltip: 'Clear Cache',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoRow(
                                Icons.storage_rounded,
                                'Storage',
                                _formatSize(sizeInBytes),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.grey[300],
                            ),
                            Expanded(
                              child: _buildInfoRow(
                                Icons.grid_on,
                                'Tiles',
                                tileCount.toString(),
                              ),
                            ),
                          ],
                        ),
                        if (cacheInfo?.lastModified != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            height: 1,
                            color: Colors.grey[200],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Last modified: ${_formatDate(cacheInfo!.lastModified!)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (isPdf) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange[800],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PDF cache can only be deleted from Basemap Management',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!isPdf && !hasCache) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No cache yet. Cache will be created when you use this basemap.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class CacheInfo {
  final int sizeInBytes;
  final int tileCount;
  final DateTime? lastModified;
  final bool isShared;

  CacheInfo({
    required this.sizeInBytes,
    required this.tileCount,
    this.lastModified,
    this.isShared = false,
  });
}
