import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../utils/lat_lng_bounds.dart';
import '../services/offline_basemap_download_service.dart';
import '../theme/app_theme.dart';
import '../models/basemap_model.dart';

class OfflineDownloadDialog extends StatefulWidget {
  final LatLngBounds visibleBounds;
  final Basemap currentBasemap;

  const OfflineDownloadDialog({
    Key? key,
    required this.visibleBounds,
    required this.currentBasemap,
  }) : super(key: key);

  @override
  State<OfflineDownloadDialog> createState() => _OfflineDownloadDialogState();
}

class _OfflineDownloadDialogState extends State<OfflineDownloadDialog> {
  int _minZoom = 10;
  int _maxZoom = 16;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  double? _estimatedSizeMB;
  bool _isCalculatingSize = false;

  final OfflineBasemapDownloadService _downloadService = OfflineBasemapDownloadService();

  @override
  void initState() {
    super.initState();
    // Set default zoom based on basemap configuration
    _minZoom = widget.currentBasemap.minZoom.toInt();
    _maxZoom = math.min(widget.currentBasemap.maxZoom.toInt(), 18);
    
    // Reasonable defaults for offline use
    if (_minZoom < 10) _minZoom = 10;
    if (_maxZoom > 16) _maxZoom = 16;
    
    // Calculate estimated size
    _calculateEstimatedSize();
  }

  Future<void> _calculateEstimatedSize() async {
    setState(() => _isCalculatingSize = true);
    
    try {
      final sizeMB = await OfflineBasemapDownloadService.estimateDownloadSize(
        bounds: widget.visibleBounds,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        urlTemplate: widget.currentBasemap.urlTemplate,
      );
      
      if (mounted) {
        setState(() {
          _estimatedSizeMB = sizeMB;
          _isCalculatingSize = false;
        });
      }
    } catch (e) {
      debugPrint('Error calculating size: $e');
      if (mounted) {
        setState(() {
          _estimatedSizeMB = null;
          _isCalculatingSize = false;
        });
      }
    }
  }

  int get _estimatedTileCount {
    return OfflineBasemapDownloadService.calculateTileCount(
      bounds: widget.visibleBounds,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );
  }



  void _startDownload() async {
    // Validation
    if (widget.currentBasemap.type == BasemapType.pdf) {
      _showError('PDF basemaps cannot be downloaded for offline use');
      return;
    }

    if (widget.currentBasemap.urlTemplate.isEmpty || 
        widget.currentBasemap.urlTemplate.startsWith('sqlite://') ||
        widget.currentBasemap.urlTemplate.startsWith('overlay://')) {
      _showError('This basemap does not support offline download');
      return;
    }

    // Confirm large downloads
    if (_estimatedTileCount > 10000) {
      final sizeText = _estimatedSizeMB != null 
          ? '~${_estimatedSizeMB!.toStringAsFixed(1)} MB'
          : 'unknown size';
      
      final confirm = await _showConfirmDialog(
        'Large Download',
        'This will download ${_estimatedTileCount.toStringAsFixed(0)} tiles ($sizeText). '
        'This may take several minutes and consume mobile data. Continue?',
      );
      if (confirm != true) return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Starting download...';
    });

    await _downloadService.downloadTilesForArea(
      basemapId: widget.currentBasemap.id,
      urlTemplate: widget.currentBasemap.urlTemplate,
      bounds: widget.visibleBounds,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            _downloadStatus = status;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _isDownloading = false);
          _showError(error);
        }
      },
      onComplete: () {
        if (mounted) {
          setState(() => _isDownloading = false);
          _showSuccess();
        }
      },
      onCancelled: () {
        if (mounted) {
          setState(() => _isDownloading = false);
          Navigator.of(context).pop();
        }
      },
    );
  }

  void _cancelDownload() {
    _downloadService.cancelDownload();
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('Continue'),
          ),
        ],
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
            Text('Download Error'),
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

  void _showSuccess() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 12),
            Text('Download Complete'),
          ],
        ),
        content: const Text(
          'Offline basemap tiles have been downloaded successfully. '
          'You can now use this area offline.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close success dialog
              Navigator.pop(context); // Close download dialog
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.download_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Download Offline Basemap',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Download tiles for offline use',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isDownloading)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isDownloading) ...[
                      // Basemap info
                      _buildInfoCard(
                        icon: Icons.map,
                        title: 'Basemap',
                        value: widget.currentBasemap.name,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(height: 16),

                      // Zoom range selector
                      const Text(
                        'Zoom Levels',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select the minimum and maximum zoom levels to download',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Min Zoom
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Min Zoom: $_minZoom',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Slider(
                              value: _minZoom.toDouble(),
                              min: widget.currentBasemap.minZoom.toDouble(),
                              max: _maxZoom.toDouble(),
                              divisions: (_maxZoom - widget.currentBasemap.minZoom.toInt()),
                              label: _minZoom.toString(),
                              onChanged: (value) {
                                setState(() {
                                  _minZoom = value.toInt();
                                });
                                _calculateEstimatedSize();
                              },
                            ),
                          ),
                        ],
                      ),

                      // Max Zoom
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Max Zoom: $_maxZoom',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Slider(
                              value: _maxZoom.toDouble(),
                              min: _minZoom.toDouble(),
                              max: math.min(widget.currentBasemap.maxZoom.toDouble(), 18),
                              divisions: (math.min(widget.currentBasemap.maxZoom.toInt(), 18) - _minZoom),
                              label: _maxZoom.toString(),
                              onChanged: (value) {
                                setState(() {
                                  _maxZoom = value.toInt();
                                });
                                _calculateEstimatedSize();
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Estimations
                      const Text(
                        'Download Estimation',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildInfoCard(
                        icon: Icons.grid_on,
                        title: 'Total Tiles',
                        value: _estimatedTileCount.toStringAsFixed(0),
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 12),

                      _buildInfoCard(
                        icon: Icons.storage,
                        title: 'Estimated Size',
                        value: _isCalculatingSize
                            ? 'Calculating...'
                            : _estimatedSizeMB != null
                                ? '~${_estimatedSizeMB!.toStringAsFixed(1)} MB'
                                : 'Unable to estimate',
                        color: Colors.orange,
                      ),

                      const SizedBox(height: 20),

                      // Warning
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Downloads may consume mobile data. Use WiFi for large downloads.',
                                style: TextStyle(
                                  color: Colors.orange[900],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Download progress
                      const SizedBox(height: 20),
                      Center(
                        child: Column(
                          children: [
                            SizedBox(
                              width: 120,
                              height: 120,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 120,
                                    height: 120,
                                    child: CircularProgressIndicator(
                                      value: _downloadProgress,
                                      strokeWidth: 8,
                                      backgroundColor: Colors.grey[200],
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                        AppTheme.primaryColor,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _downloadStatus,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please keep the app open',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                top: false,
                child: _isDownloading
                    ? ElevatedButton(
                        onPressed: _cancelDownload,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.errorColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.stop, size: 20),
                            SizedBox(width: 8),
                            Text('Cancel Download'),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        onPressed: _startDownload,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.download, size: 20),
                            SizedBox(width: 8),
                            Text('Start Download'),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
