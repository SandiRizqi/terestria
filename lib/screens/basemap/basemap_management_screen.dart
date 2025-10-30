import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../models/basemap_model.dart';
import '../../services/basemap_service.dart';
import '../../services/pdf/pdf_basemap_service.dart';
import '../../services/pdf/tile_generator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import '../../widgets/basemap/basemap_list_item.dart';
import '../../widgets/basemap/add_basemap_type_dialog.dart';
import '../../widgets/basemap/tms_basemap_dialog.dart';
import '../../widgets/basemap/pdf_zoom_settings_dialog.dart';
import 'cache_management_screen.dart';

class BasemapManagementScreen extends StatefulWidget {
  const BasemapManagementScreen({Key? key}) : super(key: key);

  @override
  State<BasemapManagementScreen> createState() => 
      _BasemapManagementScreenState();
}

class _BasemapManagementScreenState extends State<BasemapManagementScreen> {
  final BasemapService _basemapService = BasemapService();
  final PdfBasemapService _pdfService = PdfBasemapService();
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
    try {
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
      _showLoadingDialog('Validating PDF...');

      // Validate PDF
      final validation = await _pdfService.validatePdf(filePath);
      
      if (mounted) Navigator.pop(context);

      if (!validation.isValid) {
        _showError(validation.error ?? 'Invalid PDF file');
        return;
      }

      // Ask for basemap name
      final name = await _showNameDialog();
      if (name == null || name.isEmpty) return;

      // Ask for zoom settings
      TileGeneratorConfig? config;
      if (mounted) {
        config = await showDialog<TileGeneratorConfig>(
          context: context,
          builder: (context) => const PdfZoomSettingsDialog(),
        );
        
        if (config == null) return;
      }

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
        processingMessage: 'Starting...',
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

      // Start tile generation in background with config
      _processPdfBasemap(basemapId, filePath, config!);

    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _showError('Error: ${e.toString()}');
      }
    }
  }

  Future<void> _processPdfBasemap(
    String basemapId, 
    String pdfPath,
    TileGeneratorConfig config,
  ) async {
    try {
      // Extract georeferencing first to get bounds
      final georef = await _pdfService.extractGeoreferencing(pdfPath);
      
      await _pdfService.generateTilesFromPdf(
        pdfPath: pdfPath,
        basemapId: basemapId,
        config: config,
        onProgress: (progress, status) async {
          final basemaps = await _basemapService.getBasemaps();
          final basemap = basemaps.firstWhere((b) => b.id == basemapId);
          
          final updated = basemap.copyWith(
            processingProgress: progress,
            processingMessage: status,
            pdfStatus: progress < 0 
                ? PdfProcessingStatus.failed
                : progress >= 1.0 
                    ? PdfProcessingStatus.completed 
                    : PdfProcessingStatus.processing,
          );

          if (progress >= 1.0) {
            // Store SQLite reference and georeferencing bounds
            final completed = updated.copyWith(
              urlTemplate: 'sqlite://$basemapId/{z}/{x}/{y}',
              minZoom: config.minZoom ?? georef?.calculateOptimalZoomLevels()['minZoom'],
              maxZoom: config.maxZoom ?? georef?.calculateOptimalZoomLevels()['maxZoom'],
              pdfMinLat: georef?.minLat,
              pdfMinLon: georef?.minLon,
              pdfMaxLat: georef?.maxLat,
              pdfMaxLon: georef?.maxLon,
              pdfCenterLat: georef?.centerLat,
              pdfCenterLon: georef?.centerLon,
            );
            await _basemapService.saveBasemap(completed);
          } else {
            await _basemapService.saveBasemap(updated);
          }

          // No need to call _loadBasemaps here, auto-refresh will handle it
        },
      );
    } catch (e) {
      final basemaps = await _basemapService.getBasemaps();
      final basemap = basemaps.firstWhere((b) => b.id == basemapId);
      
      final failed = basemap.copyWith(
        pdfStatus: PdfProcessingStatus.failed,
        processingProgress: -1.0,
        processingMessage: 'Error: ${e.toString()}',
      );
      
      await _basemapService.saveBasemap(failed);
      // No need to call _loadBasemaps here, auto-refresh will handle it
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
          : Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildBasemapList()),
              ],
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
