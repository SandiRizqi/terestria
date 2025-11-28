import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/pdf/tile_generator.dart';

class PdfZoomSettingsDialog extends StatefulWidget {
  const PdfZoomSettingsDialog({Key? key}) : super(key: key);

  @override
  State<PdfZoomSettingsDialog> createState() => _PdfZoomSettingsDialogState();
}

class _PdfZoomSettingsDialogState extends State<PdfZoomSettingsDialog> {
  int _minZoom = 13;
  int _maxZoom = 16;
  int _dpi = 150;

  String _getQualityLabel() {
    if (_dpi <= 100) return 'Low (Faster)';
    if (_dpi <= 150) return 'Medium (Balanced)';
    if (_dpi <= 200) return 'High (Slower)';
    return 'Very High (Slowest)';
  }

  String _getSizeEstimate() {
    // Estimation dengan scaling
    // Base zoom memiliki N tiles, setiap zoom level berikutnya = 4x tiles
    final zoomLevels = _maxZoom - _minZoom + 1;
    
    // Estimasi tiles per zoom level (scaled)
    int totalTiles = 0;
    for (int i = 0; i < zoomLevels; i++) {
      int tilesAtZoom = (4 << (i * 2)); // 4, 16, 64, 256, 1024, ...
      totalTiles += tilesAtZoom;
    }
    
    // Average 50KB per tile (compressed PNG)
    final sizeMB = (totalTiles * 50) / 1024;
    
    if (sizeMB < 100) {
      return '~${sizeMB.round()}MB';
    } else if (sizeMB < 1000) {
      return '~${(sizeMB / 10).round() * 10}MB';
    } else {
      return '~${(sizeMB / 100).round() / 10}GB';
    }
  }

  String _getTimeEstimate() {
    final zoomLevels = _maxZoom - _minZoom + 1;
    
    // Time increases exponentially with zoom levels
    // Base time: 10 seconds per zoom level
    // Each level takes longer due to more tiles
    int totalSeconds = 0;
    for (int i = 0; i < zoomLevels; i++) {
      int secondsAtZoom = (10 * (1 << i)); // 10, 20, 40, 80, 160, ...
      totalSeconds += secondsAtZoom;
    }
    
    // Adjust for DPI
    totalSeconds = (totalSeconds * (_dpi / 150)).round();
    
    if (totalSeconds < 60) {
      return '~$totalSeconds seconds';
    } else if (totalSeconds < 3600) {
      return '~${(totalSeconds / 60).round()} minutes';
    } else {
      final hours = (totalSeconds / 3600).round();
      return '~$hours hour${hours > 1 ? "s" : ""}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PDF Processing Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adjust these settings based on your needs:',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            
            // Min Zoom
            const Text(
              'Minimum Zoom Level',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Lower zoom = more overview, less detail',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            Slider(
              value: _minZoom.toDouble(),
              min: 10,
              max: 16,
              divisions: 6,
              label: _minZoom.toString(),
              onChanged: (value) {
                setState(() {
                  _minZoom = value.round();
                  if (_minZoom > _maxZoom) {
                    _maxZoom = _minZoom;
                  }
                });
              },
            ),
            Text(
              'Zoom: $_minZoom',
              style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 16),
            
            // Max Zoom
            const Text(
              'Maximum Zoom Level',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Higher zoom = more detail, larger size',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            Slider(
              value: _maxZoom.toDouble(),
              min: _minZoom.toDouble(),
              max: 22, // Support sampai zoom 22 untuk detail maksimal
              divisions: (22 - _minZoom),
              label: _maxZoom.toString(),
              onChanged: (value) {
                setState(() {
                  _maxZoom = value.round();
                });
              },
            ),
            Text(
              'Zoom: $_maxZoom',
              style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 16),
            
            // DPI
            const Text(
              'Image Quality (DPI)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Higher DPI = better quality, slower processing',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            Slider(
              value: _dpi.toDouble(),
              min: 100,
              max: 250,
              divisions: 3,
              label: _getQualityLabel(),
              onChanged: (value) {
                setState(() {
                  _dpi = value.round();
                });
              },
            ),
            Text(
              '$_dpi DPI - ${_getQualityLabel()}',
              style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 20),
            
            // Estimates
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lightGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.lightGreen),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppTheme.primaryGreen),
                      SizedBox(width: 8),
                      Text(
                        'Estimated',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Processing Time:', style: TextStyle(fontSize: 12)),
                      Text(
                        _getTimeEstimate(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Storage Size:', style: TextStyle(fontSize: 12)),
                      Text(
                        _getSizeEstimate(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'High zoom levels (>18) require significant processing time and storage. Consider your device capacity.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '💡 Recommended: Zoom 13-16 (balanced), 13-18 (detailed), 13-22 (maximum detail).',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              TileGeneratorConfig(
                minZoom: _minZoom,
                maxZoom: _maxZoom,
                dpi: _dpi,
              ),
            );
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
