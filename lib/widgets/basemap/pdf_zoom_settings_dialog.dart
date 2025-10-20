import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/pdf/tile_generator.dart';

class PdfZoomSettingsDialog extends StatefulWidget {
  const PdfZoomSettingsDialog({Key? key}) : super(key: key);

  @override
  State<PdfZoomSettingsDialog> createState() => _PdfZoomSettingsDialogState();
}

class _PdfZoomSettingsDialogState extends State<PdfZoomSettingsDialog> {
  int _minZoom = 14;
  int _maxZoom = 18;
  int _dpi = 150;

  String _getQualityLabel() {
    if (_dpi <= 100) return 'Low (Faster)';
    if (_dpi <= 150) return 'Medium (Balanced)';
    if (_dpi <= 200) return 'High (Slower)';
    return 'Very High (Slowest)';
  }

  String _getSizeEstimate() {
    // Rough estimation
    final zoomLevels = _maxZoom - _minZoom + 1;
    final sizeMB = zoomLevels * 25; // Approximate 25MB per zoom level
    
    if (sizeMB < 100) {
      return '~${sizeMB}MB';
    } else if (sizeMB < 1000) {
      return '~${(sizeMB / 10).round() * 10}MB';
    } else {
      return '~${(sizeMB / 100).round() / 10}GB';
    }
  }

  String _getTimeEstimate() {
    final zoomLevels = _maxZoom - _minZoom + 1;
    final seconds = (zoomLevels * 15 * (_dpi / 150)).round();
    
    if (seconds < 60) {
      return '~$seconds seconds';
    } else {
      return '~${(seconds / 60).round()} minutes';
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
              max: 19,
              divisions: (19 - _minZoom),
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
            const Text(
              '💡 Tip: For quick preview, use zoom 14-16. For detailed work, use 14-18.',
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
