import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../../models/basemap_model.dart';
import '../../services/basemap_service.dart';
import '../../services/pdf/pdf_basemap_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import '../../widgets/basemap/basemap_list_item.dart';
import '../../widgets/basemap/add_basemap_type_dialog.dart';
import '../../widgets/basemap/tms_basemap_dialog.dart';
import 'cache_management_screen.dart';
import '../../services/geopdf_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../services/settings_service.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/basemap/cloud_basemap_dialog.dart';

class BasemapManagementScreen extends StatefulWidget {
  const BasemapManagementScreen({Key? key}) : super(key: key);

  @override
  State<BasemapManagementScreen> createState() => 
      _BasemapManagementScreenState();
}

class _BasemapManagementScreenState extends State<BasemapManagementScreen> {
  final BasemapService _basemapService = BasemapService();
  final PdfBasemapService _pdfService = PdfBasemapService();
  final SettingsService _settingsService = SettingsService();
  final ConnectivityService _connectivityService = ConnectivityService();
  final _uuid = const Uuid();
  
  List<Basemap> _basemaps = [];
  Basemap? _selectedBasemap;
  bool _isLoading = true;
  bool _hasProcessingBasemaps = false;

  @override
  void initState() {
    super.initState();
    _loadBasemaps();
  }

  Future<void> _loadBasemaps() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    
    final basemaps = await _basemapService.getBasemaps();
    final selected = await _basemapService.getSelectedBasemap();
    
    // Check if any basemap is processing
    final hasProcessing = basemaps.any((b) => b.isPdfProcessing);
    
    if (mounted) {
      setState(() {
        _basemaps = basemaps;
        _selectedBasemap = selected;
        _isLoading = false;
        _hasProcessingBasemaps = hasProcessing;
      });
      
      // Schedule next refresh if still processing
      if (hasProcessing) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _hasProcessingBasemaps) {
            _loadBasemaps();
          }
        });
      }
    }
  }

  Future<void> _addBasemap() async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => const AddBasemapTypeDialog(),
    );

    if (type == null) return;

    if (type == 'tms') {
      await _addTmsBasemap();
    } else if (type == 'pdf') {
      await _addPdfBasemap();
    } else if (type == 'cloud') {
      await _addFromCloud();
    }
  }

  Future<void> _addFromCloud() async {
    // Check connectivity first
    final isOnline = await _connectivityService.checkConnection();
    
    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You need to be online to add basemaps from cloud',
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.errorColor,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Show cloud basemap dialog
    final addedCount = await showDialog<int>(
      context: context,
      builder: (context) => const CloudBasemapDialog(),
    );

    if (addedCount != null && addedCount > 0) {
      _loadBasemaps();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$addedCount basemap(s) added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _addTmsBasemap() async {
    final basemap = await showDialog<Basemap>(
      context: context,
      builder: (context) => const TmsBasemapDialog(),
    );

    if (basemap != null) {
      await _basemapService.saveBasemap(basemap);
      _loadBasemaps();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Basemap added successfully')),
        );
      }
    }
  }

  Future<void> _addPdfBasemap() async {
    bool isShowingDialog = false;
    
    try {
      // Check if iOS and show warning
      if (Platform.isIOS) {
        final proceed = await _showIosWarning();
        if (proceed != true) return;
      }

      // Pick PDF file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.first.path;
      if (filePath == null) {
        _showError('Could not access the selected file');
        return;
      }

      // Show loading
      isShowingDialog = true;
      _showLoadingDialog('Analyzing GeoPDF file...');

      // Initialize GeoPDF service and extract metadata
      //await GeoPdfService.initialize();
      final metadata = await GeoPdfService.extractMetadata(filePath).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('PDF analysis timed out. The file may be too large or corrupted.');
        },
      );
      
      if (mounted && isShowingDialog) {
        Navigator.pop(context);
        isShowingDialog = false;
      }

      if (metadata['success'] != true) {
        _showError('Failed to read PDF: ${metadata['message']}');
        return;
      }

      // Ask for basemap name
      final name = await _showNameDialog();
      if (name == null || name.isEmpty) return;

      // REMOVED: Dialog zoom settings (tidak perlu lagi untuk overlay mode)
      // Langsung gunakan kualitas tinggi tanpa input user

      // Generate unique ID
      final basemapId = _uuid.v4();

      // Create basemap with processing status
      final basemap = Basemap(
        id: basemapId,
        name: name,
        type: BasemapType.pdf,
        urlTemplate: '',
        pdfPath: filePath,
        pdfStatus: PdfProcessingStatus.processing,
        processingProgress: 0.0,
        processingMessage: 'Initializing processor...',
        createdAt: DateTime.now(),
      );

      await _basemapService.saveBasemap(basemap);
      _loadBasemaps();

      // Show info message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Processing "$name"... Check progress in the list'),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Start overlay processing with ORIGINAL quality (FAST!)
      _processPdfBasemapWithOverlay(basemapId, filePath);

    } on TimeoutException catch (e) {
      debugPrint('❌ Timeout error: $e');
      if (mounted) {
        if (isShowingDialog) {
          Navigator.of(context).popUntil((route) => route.isFirst || !route.navigator!.canPop());
        }
        _showError('Operation timed out: ${e.message}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error adding PDF basemap: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        if (isShowingDialog) {
          Navigator.of(context).popUntil((route) => route.isFirst || !route.navigator!.canPop());
        }
        _showError('Error: ${e.toString()}');
      }
    }
  }

  // FIX: iOS-compatible path handling
  Future<String> _getBasemapOutputDir(String basemapId) async {
    final appDir = await getApplicationDocumentsDirectory();
    
    // iOS: Langsung di Documents directory (sandbox-safe)
    // Android: Tetap bisa gunakan Documents
    final outputDir = Directory('${appDir.path}/basemaps/$basemapId');
    
    // Ensure directory exists
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    
    debugPrint('📂 Basemap output dir: ${outputDir.path}');
    return outputDir.path;
  }

  Future<bool?> _showIosWarning() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.primaryColor),
            SizedBox(width: 12),
            Text('iOS Notice'),
          ],
        ),
        content: Text(
          'GeoPDF processing on iOS may use adjusted resolution (max 200 DPI) to prevent memory issues. '
          'Current setting: ${_settingsService.settings.pdfDpi} DPI. '
          'You can change this in Settings > PDF Basemap Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  // GeoPDF processing with OVERLAY mode using ORIGINAL quality (FAST!)
  Future<void> _processPdfBasemapWithOverlay(
    String basemapId,
    String pdfPath,
  ) async {
    Basemap? basemap;
    
    try {
      // FIX: Use iOS-compatible path
      final outputDir = await _getBasemapOutputDir(basemapId);
      
      // Update status
      try {
        basemap = (await _basemapService.getBasemaps())
            .firstWhere((b) => b.id == basemapId);
      } catch (e) {
        debugPrint('⚠️ Basemap not found: $basemapId');
        return; // Basemap was deleted, stop processing
      }
      
      if (mounted) {
        await _basemapService.saveBasemap(
          basemap.copyWith(
            processingProgress: 0.1,
            processingMessage: 'Extracting geographic coordinates...',
          ),
        );
      }

      // Extract coordinates using Python with timeout
      final coords = await GeoPdfService.extractCoordinates(pdfPath).timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          throw TimeoutException('Coordinate extraction timed out.');
        },
      );
      
      if (coords['success'] != true) {
        throw Exception('Failed to extract coordinates: ${coords['message']}');
      }

      final bounds = coords['bounds'];
      
      // FIX: GeoPDF service returns coordinates, but we need to verify which is lat/lon
      // Check if values are in valid range: lat (-90 to 90), lon (-180 to 180)
      var minLat = bounds['min_lat']?.toDouble() ?? -6.3;
      var minLon = bounds['min_lon']?.toDouble() ?? 106.7;
      var maxLat = bounds['max_lat']?.toDouble() ?? -6.1;
      var maxLon = bounds['max_lon']?.toDouble() ?? 106.9;
      
      // Deteksi swap koordinat
      bool needSwap = false;
      if (minLat.abs() > 90 || maxLat.abs() > 90) {
        // lat out of range → jelas swap
        needSwap = true;
        debugPrint('⚠️ Lat out of range → swapping');
      } else if (minLon.abs() <= 90 && maxLon.abs() <= 90) {
        // Keduanya dalam -90..90: pakai heuristik magnitude
        final avgAbsLat = (minLat.abs() + maxLat.abs()) / 2;
        final avgAbsLon = (minLon.abs() + maxLon.abs()) / 2;
        if (avgAbsLat > avgAbsLon) {
          needSwap = true;
          debugPrint('⚠️ Lat magnitude ($avgAbsLat) > Lon magnitude ($avgAbsLon) → swapping');
        }
      }
      if (needSwap) {
        debugPrint('   Before swap - minLat: $minLat, minLon: $minLon, maxLat: $maxLat, maxLon: $maxLon');
        final tempMinLat = minLat;
        final tempMaxLat = maxLat;
        minLat = minLon;
        maxLat = maxLon;
        minLon = tempMinLat;
        maxLon = tempMaxLat;
        debugPrint('   After swap - minLat: $minLat, minLon: $minLon, maxLat: $maxLat, maxLon: $maxLon');
      }

      // Update with coordinates
      if (mounted) {
        try {
          basemap = (await _basemapService.getBasemaps())
              .firstWhere((b) => b.id == basemapId);
        } catch (e) {
          debugPrint('⚠️ Basemap not found during update: $basemapId');
          return; // Basemap was deleted, stop processing
        }
        
        debugPrint('🗺️ Extracted bounds from PDF:');
        debugPrint('   minLat: $minLat, minLon: $minLon');
        debugPrint('   maxLat: $maxLat, maxLon: $maxLon');
        debugPrint('   centerLat: ${(minLat + maxLat) / 2}, centerLon: ${(minLon + maxLon) / 2}');
        
        await _basemapService.saveBasemap(
          basemap.copyWith(
            processingProgress: 0.3,
            processingMessage: 'Converting PDF to overlay image...',
            pdfMinLat: minLat,
            pdfMinLon: minLon,
            pdfMaxLat: maxLat,
            pdfMaxLon: maxLon,
            pdfCenterLat: (minLat + maxLat) / 2,
            pdfCenterLon: (minLon + maxLon) / 2,
          ),
        );
      }

      // FIX: iOS-optimized DPI settings with user preference
      await _settingsService.initialize();
      final userDpi = _settingsService.settings.pdfDpi;
      final dpi = Platform.isIOS 
          ? (userDpi > 200 ? 200 : userDpi) // iOS: cap at 200 DPI
          : userDpi; // Android: use user setting
      
      debugPrint('🔧 Processing with DPI: $dpi (iOS: ${Platform.isIOS})');

      // Process GeoPDF as overlay image with MOBILE-OPTIMIZED quality (MUCH FASTER!) with timeout
      final result = await GeoPdfService.processGeoPdfAsOverlay(
        pdfPath: pdfPath,
        outputDir: outputDir,
        dpi: dpi,  // Explicit DPI untuk iOS
        onProgress: (status) async {
          if (!mounted) return;
          
          // Update progress
          double progress = 0.3;
          if (status.contains('metadata')) progress = 0.4;
          else if (status.contains('coordinates')) progress = 0.5;
          else if (status.contains('overlay')) progress = 0.7;
          else if (status.contains('complete')) progress = 1.0;

          try {
            final currentBasemap = (await _basemapService.getBasemaps())
                .firstWhere((b) => b.id == basemapId);
            
            if (mounted) {
              await _basemapService.saveBasemap(
                currentBasemap.copyWith(
                  processingProgress: progress,
                  processingMessage: status,
                ),
              );
            }
          } catch (e) {
            debugPrint('⚠️ Progress update error: $e');
            // Don't throw, just log - basemap might have been deleted
          }
        },
      ).timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw TimeoutException('PDF processing timed out. Try a smaller file or lower DPI.');
        },
      );

      if (result['success'] != true) {
        throw Exception('Overlay generation failed: ${result['message']}');
      }

      // FIX: Validate overlay path exists
      final overlayPath = result['overlay_image'] as String?;
      if (overlayPath == null || !await File(overlayPath).exists()) {
        throw Exception('Overlay image not found at: $overlayPath');
      }

      debugPrint('✅ Overlay image created: $overlayPath');
      
      // Mark as completed with overlay mode
      if (mounted) {
        try {
          basemap = (await _basemapService.getBasemaps())
              .firstWhere((b) => b.id == basemapId);
        } catch (e) {
          debugPrint('⚠️ Basemap not found at completion: $basemapId');
          return; // Basemap was deleted, stop processing
        }
        
        final imageSizeMB = result['image_size_mb']?.toStringAsFixed(2) ?? '0';
        final imageWidth = result['image_width'] ?? 0;
        final imageHeight = result['image_height'] ?? 0;
        final dpiUsed = dpi.toString();
        
        final completed = basemap.copyWith(
          urlTemplate: 'overlay://$basemapId',  // Special URL for overlay mode
          pdfOverlayImagePath: overlayPath,
          useOverlayMode: true,
          minZoom: 10,
          maxZoom: 22,
          pdfStatus: PdfProcessingStatus.completed,
          processingProgress: 1.0,
          processingMessage: '✅ Ready! (${imageWidth}x${imageHeight}, ${imageSizeMB} MB @ $dpiUsed DPI)'
        );

        await _basemapService.saveBasemap(completed);
        
        // Reload to show updated status
        if (mounted) {
          _loadBasemaps();
        }
      }

    } on TimeoutException catch (e) {
      debugPrint('❌ Processing timeout: $e');
      
      // Mark as failed
      try {
        if (basemap == null) {
          basemap = (await _basemapService.getBasemaps())
              .firstWhere((b) => b.id == basemapId);
        }
        
        if (mounted) {
          final failed = basemap.copyWith(
            pdfStatus: PdfProcessingStatus.failed,
            processingProgress: -1.0,
            processingMessage: '❌ Timeout: ${e.message}',
          );
          
          await _basemapService.saveBasemap(failed);
          _loadBasemaps();
        }
      } catch (saveError) {
        debugPrint('❌ Failed to save timeout state: $saveError');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Processing error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Mark as failed
      try {
        if (basemap == null) {
          basemap = (await _basemapService.getBasemaps())
              .firstWhere((b) => b.id == basemapId);
        }
        
        if (mounted) {
          final failed = basemap.copyWith(
            pdfStatus: PdfProcessingStatus.failed,
            processingProgress: -1.0,
            processingMessage: '❌ Error: ${e.toString()}',
          );
          
          await _basemapService.saveBasemap(failed);
          _loadBasemaps();
        }
      } catch (saveError) {
        debugPrint('❌ Failed to save error state: $saveError');
      }
    }
  }



  Future<void> _editBasemap(Basemap basemap) async {
    final updated = await showDialog<Basemap>(
      context: context,
      builder: (context) => TmsBasemapDialog(basemap: basemap),
    );

    if (updated != null) {
      await _basemapService.saveBasemap(updated);
      _loadBasemaps();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Basemap updated successfully')),
        );
      }
    }
  }

  Future<void> _deleteBasemap(Basemap basemap) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Basemap'),
        content: Text('Are you sure you want to delete "${basemap.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Delete tiles if PDF basemap
      if (basemap.isPdfBasemap) {
        await _pdfService.deleteTiles(basemap.id);
      }
      
      await _basemapService.deleteBasemap(basemap.id);
      _loadBasemaps();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Basemap deleted successfully')),
        );
      }
    }
  }

  Future<void> _selectBasemap(Basemap basemap) async {
    await _basemapService.setSelectedBasemap(basemap.id);
    setState(() => _selectedBasemap = basemap);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${basemap.name} selected')),
      );
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
          children:  [
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

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name Your Basemap'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Basemap Name',
            hintText: 'e.g., Survey Area Map',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Basemap Management'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.storage_rounded),
            tooltip: 'Cache Management',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CacheManagementScreen(),
                ),
              );
            },
          ),
          const ConnectivityIndicator(showLabel: false, iconSize: 24),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false, // AppBar sudah aman
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildBasemapList()),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBasemap,
        child: const Icon(Icons.add),
      ),

    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
      padding: const EdgeInsets.all(AppTheme.spacingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manage Your Basemaps',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add TMS basemaps or upload GeoPDF maps',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasemapList() {
    return ListView.builder(
      padding: const EdgeInsets.only(
        left: AppTheme.spacingMedium,
        right: AppTheme.spacingMedium,
        top: AppTheme.spacingMedium,
        bottom: 80, // Padding untuk FAB
      ),
      itemCount: _basemaps.length,
      itemBuilder: (context, index) {
        final basemap = _basemaps[index];
        final isSelected = _selectedBasemap?.id == basemap.id;
        final isBuiltin = basemap.type == BasemapType.builtin;

        return BasemapListItem(
          basemap: basemap,
          isSelected: isSelected,
          onTap: () => _selectBasemap(basemap),
          onEdit: !isBuiltin && !basemap.isPdfBasemap 
              ? () => _editBasemap(basemap) 
              : null,
          onDelete: !isBuiltin ? () => _deleteBasemap(basemap) : null,
        );
      },
    );
  }
}
