import 'package:flutter/material.dart';
import 'package:geoform_app/config/api_config.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../models/project_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/basemap_model.dart';
import '../../models/form_field_model.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../services/basemap_service.dart';
import '../../services/tile_providers/local_file_tile_provider.dart';
import '../../services/tile_cache_service.dart';
import '../../widgets/dynamic_form.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:path_provider/path_provider.dart';
import '../basemap/basemap_management_screen.dart';
import 'package:path_provider/path_provider.dart';




enum CollectionMode { tracking, drawing }

class DataCollectionScreen extends StatefulWidget {
  final Project project;

  const DataCollectionScreen({Key? key, required this.project}) : super(key: key);

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen> {
  final LocationService _locationService = LocationService();
  final StorageService _storageService = StorageService();
  final BasemapService _basemapService = BasemapService();
  final MapController _mapController = MapController();
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  List<GeoPoint> _collectedPoints = [];
  GeoPoint? _currentLocation;
  StreamSubscription<GeoPoint>? _locationSubscription;
  StreamSubscription? _backgroundServiceSubscription;
  bool _isTracking = false;
  bool _isPaused = false;
  bool _isSaving = false;
  Map<String, dynamic> _formData = {};
  CollectionMode _collectionMode = CollectionMode.tracking;
  Basemap? _selectedBasemap;
  Future<String>? _cachePathFuture;
  bool _showForm = false;
  bool _isFormValid = false;
  bool _isLoadingLocation = true;
  
  // Existing data from project
  List<GeoData> _existingData = [];
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _loadBasemap();
    _loadExistingData();
    _cachePathFuture = _getCachePath();
  }

  Future<void> _loadExistingData() async {
    setState(() => _isLoadingData = true);
    try {
      final data = await _storageService.loadGeoData(widget.project.id);
      setState(() {
        _existingData = data;
        _isLoadingData = false;
      });
    } catch (e) {
      print('Error loading existing data: $e');
      setState(() => _isLoadingData = false);
    }
  }

  Future<String> _getCachePath() async {
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}${Platform.pathSeparator}MapTiles';
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _backgroundServiceSubscription?.cancel();
    if (_isTracking) {
      _locationService.stopBackgroundTracking();
    }
    super.dispose();
  }

  Future<void> _loadBasemap() async {
    final basemap = await _basemapService.getSelectedBasemap();
    setState(() => _selectedBasemap = basemap);
  }

  Future<void> _initializeLocation() async {
    setState(() => _isLoadingLocation = true);
    
    final location = await _locationService.getCurrentLocation();
    
    if (mounted) {
      setState(() => _isLoadingLocation = false);
    }
    
    if (location != null) {
      setState(() {
        _currentLocation = location;
      });
      _mapController.move(
        LatLng(location.latitude, location.longitude),
        15,
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to get location. Please enable location services.'),
          ),
        );
      }
    }
  }

  void _toggleTracking() {
    if (_isTracking) {
      _finishTracking();
    } else {
      _startTracking();
    }
  }

  void _togglePause() {
    if (_isPaused) {
      _resumeTracking();
    } else {
      _pauseTracking();
    }
  }

  void _startTracking() async {
    // iOS: Use native location background mode
    // Android: Use background service
    if (Platform.isIOS) {
      // Enable iOS background location
      await _locationService.location.enableBackgroundMode(enable: true);
      
      // Use regular location stream (iOS handles background automatically)
      _locationSubscription = _locationService.trackLocation().listen((location) {
        if (mounted) {
          setState(() {
            _currentLocation = location;
            if (!_isPaused) {
              _collectedPoints.add(location);
            }
          });
          
          _mapController.move(
            LatLng(location.latitude, location.longitude),
            _mapController.camera.zoom,
          );
        }
      });
    } else {
      // Android: Start background service
      await _locationService.startBackgroundTracking();
      
      // Listen to background location stream
      _locationSubscription = _locationService.backgroundLocationStream.listen((location) {
        if (mounted) {
          setState(() {
            _currentLocation = location;
            if (!_isPaused) {
              _collectedPoints.add(location);
            }
          });
          
          _mapController.move(
            LatLng(location.latitude, location.longitude),
            _mapController.camera.zoom,
          );
        }
      });
    }

    setState(() {
      _isTracking = true;
      _isPaused = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Platform.isIOS 
          ? 'Tracking started - ensure "Always Allow" location permission'
          : 'Tracking started - will continue in background'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _pauseTracking() async {
    if (Platform.isAndroid) {
      await _locationService.pauseBackgroundTracking();
    }
    setState(() => _isPaused = true);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tracking paused'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _resumeTracking() async {
    if (Platform.isAndroid) {
      await _locationService.resumeBackgroundTracking();
    }
    setState(() => _isPaused = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tracking resumed'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _finishTracking() async {
    if (Platform.isIOS) {
      await _locationService.location.enableBackgroundMode(enable: false);
    } else {
      await _locationService.stopBackgroundTracking();
    }
    _locationSubscription?.cancel();
    setState(() {
      _isTracking = false;
      _isPaused = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tracking finished'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _addCurrentPoint() async {
    final location = await _locationService.getCurrentLocation();
    if (location != null) {
      setState(() {
        _collectedPoints.add(location);
        // _checkAndShowForm();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Point added'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _checkAndShowForm() {
    // Show form after minimum points collected
    if (!_showForm) {
      if (widget.project.geometryType == GeometryType.point && _collectedPoints.length >= 1) {
        setState(() => _showForm = true);
      } else if (widget.project.geometryType == GeometryType.line && _collectedPoints.length >= 2) {
        setState(() => _showForm = true);
      } else if (widget.project.geometryType == GeometryType.polygon && _collectedPoints.length >= 3) {
        setState(() => _showForm = true);
      }
    }
  }


  void _validateForm() {
    // Validate the form and update button state
    if (_formKey.currentState != null) {
      final isValid = _formKey.currentState!.validate();
      setState(() {
        _isFormValid = isValid;
      });
    }
  }

  void _undoLastPoint() {
    if (_collectedPoints.isNotEmpty) {
      setState(() {
        _collectedPoints.removeLast();
        // Hide form if below minimum points
        if (widget.project.geometryType == GeometryType.point && _collectedPoints.isEmpty) {
          _showForm = false;
        } else if (widget.project.geometryType == GeometryType.line && _collectedPoints.length < 2) {
          _showForm = false;
        } else if (widget.project.geometryType == GeometryType.polygon && _collectedPoints.length < 3) {
          _showForm = false;
        }
      });
    }
  }

  void _clearPoints() {
    setState(() {
      _collectedPoints.clear();
      _showForm = false;
      _isFormValid = false;
    });
  }

  Future<void> _saveData() async {
    if (_collectedPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please collect at least one point')),
      );
      return;
    }

    // Validate form but check if errors are only from photo fields
    final isValid = _formKey.currentState!.validate();
    
    if (!isValid) {
      // Check if any photo field has errors
      bool hasPhotoErrors = false;
      bool hasOtherErrors = false;
      
      // Try to save to get the form data
      _formKey.currentState!.save();
      
      // Show warning for photo fields but allow saving
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Some fields may not meet requirements. Please review before saving.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange[700],
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Don't return - allow to continue saving
    } else {
      _formKey.currentState!.save();
    }

    // Validate geometry requirements
    if (widget.project.geometryType == GeometryType.line && _collectedPoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Line requires at least 2 points')),
      );
      return;
    }

    if (widget.project.geometryType == GeometryType.polygon && _collectedPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Polygon requires at least 3 points')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final geoData = GeoData(
        id: _uuid.v4(),
        projectId: widget.project.id,
        formData: _formData,
        points: _collectedPoints,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _storageService.saveGeoData(geoData);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data saved successfully')),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving data: $e')),
        );
      }
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_collectionMode == CollectionMode.drawing && !_isTracking) {
      final geoPoint = GeoPoint(
        latitude: point.latitude,
        longitude: point.longitude,
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _collectedPoints.add(geoPoint);
      });
    }
  }

  void _onExistingDataTap(GeoData data) {
    _showDataDetail(data);
  }

  bool _isPhotoField(String fieldName) {
    final field = widget.project.formFields.where((f) => f.label == fieldName).firstOrNull;
    if (field != null) {
      return field.type == FieldType.photo;
    }
    
    final lowerName = fieldName.toLowerCase();
    return lowerName.contains('photo') || 
           lowerName.contains('image') || 
           lowerName.contains('picture') ||
           lowerName.contains('foto') ||
           lowerName.contains('gambar');
  }

  IconData _getGeometryIcon() {
    switch (widget.project.geometryType) {
      case GeometryType.point:
        return Icons.location_on;
      case GeometryType.line:
        return Icons.timeline;
      case GeometryType.polygon:
        return Icons.polyline;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showFullImage(String imagePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Photo'),
            backgroundColor: Colors.black,
          ),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(File(imagePath)),
            ),
          ),
        ),
      ),
    );
  }

  void _showDataDetail(GeoData data) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getGeometryIcon(),
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Survey Data Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(data.createdAt),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildDataDetailContent(data),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataDetailContent(GeoData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photo fields
        ...data.formData.entries.where((entry) => _isPhotoField(entry.key)).map((entry) {
          List<String> photoPaths = [];
          if (entry.value is List) {
            photoPaths = (entry.value as List).map((e) => e.toString()).toList();
          } else if (entry.value is String && entry.value.toString().isNotEmpty) {
            photoPaths = [entry.value.toString()];
          }
          
          if (photoPaths.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.photo_camera,
                        size: 20,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (photoPaths.length > 1)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: photoPaths.length,
                    itemBuilder: (context, index) {
                      final photoFile = File(photoPaths[index]);
                      return GestureDetector(
                        onTap: () => photoFile.existsSync() ? _showFullImage(photoPaths[index]) : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: photoFile.existsSync()
                              ? Image.file(photoFile, fit: BoxFit.cover)
                              : Container(
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.image_not_supported, size: 40),
                                ),
                        ),
                      );
                    },
                  )
                else
                  GestureDetector(
                    onTap: () {
                      final photoFile = File(photoPaths[0]);
                      if (photoFile.existsSync()) _showFullImage(photoPaths[0]);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: File(photoPaths[0]).existsSync()
                          ? Image.file(File(photoPaths[0]), height: 250, width: double.infinity, fit: BoxFit.cover)
                          : Container(
                              height: 250,
                              color: Colors.grey[200],
                              child: const Icon(Icons.image_not_supported, size: 64),
                            ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            );
          }
          return const SizedBox.shrink();
        }),
        
        // Non-photo form fields
        if (data.formData.entries.any((entry) => !_isPhotoField(entry.key))) ...[
          const Row(
            children: [
              Icon(Icons.description_outlined, size: 20, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text('Form Data', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          ...data.formData.entries.where((entry) => !_isPhotoField(entry.key)).map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.key,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(entry.value.toString(), style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
        
        // Location info
        const Row(
          children: [
            Icon(Icons.my_location, size: 20, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Text('Location Points', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                '${data.points.length} point${data.points.length > 1 ? "s" : ""} recorded',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showBasemapSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => BasemapSelectorSheet(
        currentBasemap: _selectedBasemap,
        onBasemapSelected: (basemap) {
          setState(() => _selectedBasemap = basemap);
          _basemapService.setSelectedBasemap(basemap.id);
        },
      ),
    );
  }

  void _showFormBottomSheet() {
    // Initialize form validity based on whether there are required fields
    setState(() {
      _isFormValid = !widget.project.formFields.any((field) => field.required);
    });
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMedium,
                  vertical: AppTheme.spacingSmall,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Survey Data',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Scrollable Form Content
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(AppTheme.spacingMedium),
                    children: [
                      DynamicForm(
                        formFields: widget.project.formFields,
                        onSaved: (data) => _formData = data,
                        onChanged: () {
                          // Delay check to allow validation to complete
                          Future.delayed(const Duration(milliseconds: 100), () {
                            _validateForm();
                          });
                        },
                      ),
                      const SizedBox(height: AppTheme.spacingMedium),
                      
                      // Save Button at bottom of form
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_isSaving || !_isFormValid) ? null : () {
                            _saveData();
                            Navigator.pop(context);
                          },
                          icon: _isSaving 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(_isSaving ? 'Saving...' : 'Save Data'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: _isFormValid ? AppTheme.primaryColor : Colors.grey,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey[300],
                            disabledForegroundColor: Colors.grey[500],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingMedium),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      setState(() => _showForm = false);
    });
  }

  List<Widget> _buildExistingDataLayers() {
    List<Widget> layers = [];

    // Group existing data by geometry type for rendering
    for (var data in _existingData) {
      // Line/Polygon layers
      if (widget.project.geometryType == GeometryType.line) {
        layers.add(PolylineLayer(
          polylines: [
            Polyline(
              points: data.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
              color: Colors.blue.withOpacity(0.6),
              strokeWidth: 2.5,
            ),
          ],
        ));
      } else if (widget.project.geometryType == GeometryType.polygon) {
        if (data.points.length >= 3) {
          layers.add(PolygonLayer(
            polygons: [
              Polygon(
                points: data.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                color: Colors.blue.withOpacity(0.15),
                borderColor: Colors.blue.withOpacity(0.6),
                borderStrokeWidth: 2.5,
                isFilled: true,
              ),
            ],
          ));
        }
      }
      
      // Point markers for existing data (clickable)
      if (widget.project.geometryType == GeometryType.point && data.points.isNotEmpty) {
        layers.add(MarkerLayer(
          markers: [
            Marker(
              point: LatLng(data.points.first.latitude, data.points.first.longitude),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => _onExistingDataTap(data),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ));
      } else if (widget.project.geometryType == GeometryType.line && data.points.isNotEmpty) {
        // Add clickable marker at the center point of the line
        final centerIndex = data.points.length ~/ 2;
        layers.add(MarkerLayer(
          markers: [
            Marker(
              point: LatLng(
                data.points[centerIndex].latitude,
                data.points[centerIndex].longitude,
              ),
              width: 32,
              height: 32,
              child: GestureDetector(
                onTap: () => _onExistingDataTap(data),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ));
      } else if (widget.project.geometryType == GeometryType.polygon && data.points.length >= 3) {
        // Add clickable marker at the centroid of the polygon
        double sumLat = 0;
        double sumLng = 0;
        for (var point in data.points) {
          sumLat += point.latitude;
          sumLng += point.longitude;
        }
        final centroidLat = sumLat / data.points.length;
        final centroidLng = sumLng / data.points.length;
        
        layers.add(MarkerLayer(
          markers: [
            Marker(
              point: LatLng(centroidLat, centroidLng),
              width: 32,
              height: 32,
              child: GestureDetector(
                onTap: () => _onExistingDataTap(data),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ));
      }
    }

    return layers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Collect ${widget.project.geometryType.toString().split('.').last.toUpperCase()}'),
        actions: [
          const ConnectivityIndicator(
            showLabel: false,
            iconSize: 24,
          ),
          const SizedBox(width: 8),
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _collectedPoints.isEmpty ? null : () {
                setState(() => _showForm = true);
                _showFormBottomSheet();
              },
              tooltip: 'Save Data',
            ),
        ],
      ),
      body: _buildMap(),
      bottomNavigationBar: _buildBottomControls(),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FutureBuilder<String>(
          future: _cachePathFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            
            // Show loading overlay when getting location
            if (_isLoadingLocation) {
              return Container(
                color: Colors.white,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Getting your location...',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            
            final cachePath = snapshot.data!;
            
            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation != null
                    ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
                    : const LatLng(-6.2088, 106.8456),
                initialZoom: 15,
                onTap: _onMapTap,
              ),
              children: [
                // Basemap Layer
                if (_selectedBasemap != null)
                  _selectedBasemap!.isPdfBasemap
                      ? TileLayer(
                          urlTemplate: '', // Not used for local files
                          minZoom: _selectedBasemap!.minZoom.toDouble(),
                          maxZoom: _selectedBasemap!.maxZoom.toDouble(),
                          tileProvider: LocalFileTileProvider(
                            _selectedBasemap!.urlTemplate, // This contains the base path
                          ),
                        )
                      : TileLayer(
                          urlTemplate: _selectedBasemap!.urlTemplate,
                          userAgentPackageName: ApiConfig.bundleName,
                          minZoom: _selectedBasemap!.minZoom.toDouble(),
                          maxZoom: _selectedBasemap!.maxZoom.toDouble(),
                          tileProvider: CachedTileProvider(
                            store: HiveCacheStore(
                              cachePath,
                              hiveBoxName: TileCacheService.getHiveBoxName(_selectedBasemap!.id),
                            ),
                            maxStale: const Duration(days: 30),
                          ),
                        )
                else
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: ApiConfig.bundleName,
                    tileProvider: CachedTileProvider(
                      store: HiveCacheStore(
                        cachePath,
                        hiveBoxName: TileCacheService.getHiveBoxName('default_osm'),
                      ),
                      maxStale: const Duration(days: 30),
                    ),
                  ),
                
                // Existing Data Layers (from project)
                ..._buildExistingDataLayers(),
                
                // Collected Points Layers (currently being collected)
                if (_collectedPoints.isNotEmpty) ...[
                    // Line/Polygon stroke
                    if (widget.project.geometryType == GeometryType.line ||
                        widget.project.geometryType == GeometryType.polygon)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _collectedPoints
                                .map((p) => LatLng(p.latitude, p.longitude))
                                .toList(),
                            color: widget.project.geometryType == GeometryType.line
                                ? AppTheme.lineColor
                                : AppTheme.polygonColor,
                            strokeWidth: 3,
                          ),
                        ],
                      ),
                    
                    // Polygon fill
                    if (widget.project.geometryType == GeometryType.polygon &&
                        _collectedPoints.length >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _collectedPoints
                                .map((p) => LatLng(p.latitude, p.longitude))
                                .toList(),
                            color: AppTheme.polygonColor.withOpacity(0.3),
                            borderColor: AppTheme.polygonColor,
                            borderStrokeWidth: 3,
                          ),
                        ],
                      ),
                    
                    // Point markers: hanya first dan last
                    MarkerLayer(
                      markers: [
                        // First point
                        Marker(
                          point: LatLng(
                            _collectedPoints.first.latitude,
                            _collectedPoints.first.longitude,
                          ),
                          width: 24,
                          height: 24,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.green, // bisa beda warna
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Center(
                              child: Text(
                                '1',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Last point (jika lebih dari 1)
                        if (_collectedPoints.length > 1)
                          Marker(
                            point: LatLng(
                              _collectedPoints.last.latitude,
                              _collectedPoints.last.longitude,
                            ),
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red, // beda warna dari first
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  '${_collectedPoints.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                
                // Current Location Marker
                if (_currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          _currentLocation!.latitude,
                          _currentLocation!.longitude,
                        ),
                        width: 60,
                        height: 60,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: AppTheme.currentLocationColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.my_location,
                              color: AppTheme.pointColor,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
        
        // Info Card Overlay
        Positioned(
          top: AppTheme.spacingMedium,
          left: AppTheme.spacingMedium,
          right: AppTheme.spacingMedium,
          child: _buildInfoCard(),
        ),
        
        // Basemap Selector Button
        Positioned(
          bottom : AppTheme.spacingLarge,
          right: AppTheme.spacingMedium,
          child: FloatingActionButton(
            heroTag: 'basemap',
            mini: true,
            backgroundColor: Colors.white,
            child: const Icon(Icons.layers, color: AppTheme.primaryColor),
            onPressed: _showBasemapSelector,
          ),
        ),
        
        // Mode Toggle Button (only for line/polygon)
        if (widget.project.geometryType != GeometryType.point)
          Positioned(
            bottom: AppTheme.spacingMedium + 60,
            right: AppTheme.spacingMedium,
            child: FloatingActionButton(
              heroTag: 'mode',
              mini: true,
              backgroundColor: _collectionMode == CollectionMode.drawing
                  ? AppTheme.primaryColor
                  : Colors.white,
              child: Icon(
                _collectionMode == CollectionMode.drawing ? Icons.edit : Icons.gps_fixed,
                color: _collectionMode == CollectionMode.drawing ? Colors.white : AppTheme.primaryColor,
              ),
              onPressed: () {
                setState(() {
                  if (_collectionMode == CollectionMode.tracking) {
                    _collectionMode = CollectionMode.drawing;
                    if (_isTracking) _finishTracking();
                  } else {
                    _collectionMode = CollectionMode.tracking;
                  }
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _buildInfoCard() {
    double? distance;
    double? area;

    if (_collectedPoints.length >= 2) {
      if (widget.project.geometryType == GeometryType.line) {
        distance = _locationService.calculateLineDistance(_collectedPoints);
      } else if (widget.project.geometryType == GeometryType.polygon && _collectedPoints.length >= 3) {
        area = _locationService.calculatePolygonArea(_collectedPoints);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  _collectionMode == CollectionMode.drawing 
                    ? Icons.edit 
                    : _isTracking 
                      ? (_isPaused ? Icons.pause_circle : Icons.gps_fixed)
                      : Icons.gps_not_fixed,
                  color: _collectionMode == CollectionMode.drawing 
                    ? AppTheme.primaryColor 
                    : _isTracking 
                      ? (_isPaused ? Colors.orange : Colors.green)
                      : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _collectionMode == CollectionMode.drawing 
                    ? 'Drawing Mode' 
                    : _isTracking 
                      ? (_isPaused ? 'Tracking Paused' : 'Tracking Active')
                      : 'Tracking Inactive',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text('Points: ${_collectedPoints.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (_collectionMode == CollectionMode.drawing) ...[
              const SizedBox(height: 4),
              Text('Tap on map to add points', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
            ],
            if (distance != null) ...[const SizedBox(height: 8), Text('Distance: ${distance.toStringAsFixed(2)} m')],
            if (area != null) ...[const SizedBox(height: 8), Text('Area: ${area.toStringAsFixed(2)} m²')],
            if (_currentLocation != null) ...[
              const SizedBox(height: 8),
              Text('Accuracy: ±${_currentLocation!.accuracy?.toStringAsFixed(1) ?? 'N/A'} m',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tracking mode controls
            if (widget.project.geometryType != GeometryType.point && 
                _collectionMode == CollectionMode.tracking) ...[
              Row(
                children: [
                  // Start/Finish button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _toggleTracking,
                      icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow, size: 20),
                      label: Text(
                        _isTracking ? 'Finish' : 'Start',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: _isTracking ? Colors.red : AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  
                  // Pause/Resume button (only when tracking)
                  if (_isTracking) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _togglePause,
                        icon: Icon(
                          _isPaused ? Icons.play_arrow : Icons.pause,
                          size: 20,
                        ),
                        label: Text(
                          _isPaused ? 'Resume' : 'Pause',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: _isPaused ? Colors.green : Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
            
            // Bottom row: Add Point, Undo, Clear
            Row(
              children: [
                // Add Point button
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: (_isTracking || _collectionMode == CollectionMode.drawing) 
                        ? null 
                        : _addCurrentPoint,
                    icon: const Icon(Icons.add_location, size: 20),
                    label: Text(
                      widget.project.geometryType == GeometryType.point 
                          ? 'Use Location' 
                          : 'Add Point',
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[500],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                
                // Undo button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _collectedPoints.isEmpty ? null : _undoLastPoint,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Undo', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: AppTheme.primaryColor,
                      side: BorderSide(
                        color: _collectedPoints.isEmpty 
                            ? Colors.grey[300]! 
                            : AppTheme.primaryColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                
                // Clear button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _collectedPoints.isEmpty ? null : _clearPoints,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: Colors.red,
                      side: BorderSide(
                        color: _collectedPoints.isEmpty 
                            ? Colors.grey[300]! 
                            : Colors.red,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BasemapSelectorSheet extends StatefulWidget {
  final Basemap? currentBasemap;
  final Function(Basemap) onBasemapSelected;

  const BasemapSelectorSheet({Key? key, required this.currentBasemap, required this.onBasemapSelected}) : super(key: key);

  @override
  State<BasemapSelectorSheet> createState() => _BasemapSelectorSheetState();
}

class _BasemapSelectorSheetState extends State<BasemapSelectorSheet> {
  final BasemapService _basemapService = BasemapService();
  List<Basemap> _basemaps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBasemaps();
  }

  Future<void> _loadBasemaps() async {
    final basemaps = await _basemapService.getBasemaps();
    setState(() {
      _basemaps = basemaps;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Select Basemap', style: Theme.of(context).textTheme.titleLarge),
              TextButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Manage'),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BasemapManagementScreen(),
                    ),
                  ).then((_) => _loadBasemaps());
                },
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _basemaps.length,
                itemBuilder: (context, index) {
                  final basemap = _basemaps[index];
                  final isSelected = widget.currentBasemap?.id == basemap.id;
                  return ListTile(
                    leading: Icon(Icons.map, color: isSelected ? AppTheme.primaryColor : Colors.grey),
                    title: Text(basemap.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text(basemap.type == BasemapType.builtin ? 'Built-in' : 'Custom', style: const TextStyle(fontSize: 12)),
                    trailing: isSelected ? Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                    onTap: () {
                      widget.onBasemapSelected(basemap);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
