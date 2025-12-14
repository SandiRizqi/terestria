import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geoform_app/config/api_config.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_compass/flutter_compass.dart';
import '../../models/project_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/basemap_model.dart';
import '../../models/form_field_model.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../services/basemap_service.dart';
import '../../services/tile_cache_sqlite_service.dart';
import '../../services/tile_providers/sqlite_cached_tile_provider.dart';
import '../../services/tile_providers/geopdf_overlay_provider.dart';
import '../../widgets/dynamic_form.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import '../../theme/app_theme.dart';
import 'widgets/collapsible_bottom_controls.dart';
import 'widgets/user_location_marker.dart';
import '../basemap/basemap_management_screen.dart';
import '../location/location_provider_screen.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../models/settings/app_settings.dart';
import '../../widgets/offline_download_dialog.dart';
import '../../utils/lat_lng_bounds.dart' as custom_bounds;




enum CollectionMode { tracking, drawing }

class DataCollectionScreen extends StatefulWidget {
  final Project project;

  const DataCollectionScreen({Key? key, required this.project}) : super(key: key);

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final LocationService _locationService = LocationService();
  final StorageService _storageService = StorageService();
  final BasemapService _basemapService = BasemapService();
  final TileCacheSqliteService _tileCacheService = TileCacheSqliteService();
  final SettingsService _settingsService = SettingsService();
  final MapController _mapController = MapController();
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  List<GeoPoint> _collectedPoints = [];
  GeoPoint? _currentLocation;
  // 🔧 FIX: Single unified stream for both tracking and blue marker
  StreamSubscription<GeoPoint>? _unifiedLocationSubscription;
  bool _isTracking = false;
  bool _isPaused = false;
  bool _isSaving = false;
  Map<String, dynamic> _formData = {};
  CollectionMode _collectionMode = CollectionMode.tracking;
  Basemap? _selectedBasemap;
  bool _showForm = false;
  bool _isLoadingLocation = true;
  bool _hasInitialZoom = false;
  double _currentBearing = 0.0;
  StreamSubscription<CompassEvent>? _compassSubscription;
  bool _isBottomSheetExpanded = false;
  LatLng _centerCoordinates = const LatLng(-6.2088, 106.8456);
  
  // Existing data from project
  List<GeoData> _existingData = [];
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _setTransparentStatusBar();
    _initializeSettings();
    _initializeLocation();
    _loadBasemap();
    _loadExistingData();
    _initCompass();
    
    // 🔧 NEW: Restore tracking state if coming back to screen
    _restoreTrackingState();
  }
  
  void _setTransparentStatusBar() {
    // Set status bar transparan
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
  }
  
  void _restoreTrackingState() {
    // Check if tracking was active when we left this screen
    if (_locationService.isActivelyTracking) {
      print('🔄 Restoring tracking state...');
      setState(() {
        _isTracking = true;
        // Restore collected points from service
        _collectedPoints = List.from(_locationService.activeTrackingPoints);
      });
      print('✅ Restored ${_collectedPoints.length} points');
    }
  }

  Future<void> _initializeSettings() async {
    await _settingsService.initialize();
  }

  void _initCompass() {
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (mounted && event.heading != null) {
        setState(() {
          _currentBearing = event.heading!;
        });
      }
    });
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

  @override
  void dispose() {
    // 🔧 CRITICAL FIX: DON'T stop tracking when navigating away
    // Only cleanup UI-related streams
    
    // Cancel compass stream (UI only)
    _compassSubscription?.cancel();
    
    // ⚠️ DON'T cancel location stream if tracking is active!
    // Let it continue in background
    if (!_isTracking) {
      // Only cancel if NOT tracking (just viewing)
      _unifiedLocationSubscription?.cancel();
      print('🗑️ Cancelled location stream (not tracking)');
    } else {
      // Keep stream alive for background tracking
      print('✅ Keeping location stream alive (tracking active)');
      // DON'T cancel _unifiedLocationSubscription
      // DON'T stop background service
    }
    
    super.dispose();
  }

  Future<void> _loadBasemap() async {
    final basemap = await _basemapService.getSelectedBasemap();
    
    if (mounted) {
      setState(() => _selectedBasemap = basemap);
      
      // Jika PDF basemap dengan georeferencing, zoom ke bounds PDF
      if (basemap.type == BasemapType.pdf && basemap.hasPdfGeoreferencing) {
        print('📍 PDF Basemap loaded, will zoom to bounds...');
        print('   Bounds: Lat[${basemap.pdfMinLat}, ${basemap.pdfMaxLat}] Lon[${basemap.pdfMinLon}, ${basemap.pdfMaxLon}]');
        
        // PENTING: Delay lebih lama dan pastikan map controller ready
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted && _mapController.camera != null) {
            try {
              // FIX: LatLngBounds constructor menerima southwest dan northeast corners
              // southwest = LatLng(minLat, minLon)
              // northeast = LatLng(maxLat, maxLon)
              final bounds = LatLngBounds(
                LatLng(basemap.pdfMinLat!, basemap.pdfMinLon!),  // southwest corner
                LatLng(basemap.pdfMaxLat!, basemap.pdfMaxLon!),  // northeast corner
              );
              
              print('🔍 Fitting map to PDF bounds...');
              print('   Southwest: ${bounds.southWest}');
              print('   Northeast: ${bounds.northEast}');
              
              // Fit bounds dengan padding
              _mapController.fitCamera(
                CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(50),
                ),
              );
              
              print('✅ Map zoomed to PDF bounds');
              print('📷 New camera center: ${_mapController.camera.center}');
              print('📷 New camera zoom: ${_mapController.camera.zoom}');
            } catch (e) {
              print('❌ Error fitting bounds: $e');
            }
          }
        });
      }
    }
  }

  Future<void> _initializeLocation() async {
    setState(() => _isLoadingLocation = true);
    
    // Load provider settings first
    await _locationService.loadLocationSettings();
    
    // 🔧 FIX: Start unified persistent stream immediately
    _startUnifiedLocationStream();
    
    // Try to get initial location for map centering
    GeoPoint? location;
    
    if (_locationService.currentProvider == LocationProvider.emlid) {
      // For Emlid, wait a bit for first data
      if (_locationService.isEmlidConnected) {
        try {
          location = await _locationService.trackEmlidLocation()
            .timeout(const Duration(seconds: 3))
            .first;
        } catch (e) {
          print('Waiting for Emlid data: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Waiting for GPS data...'),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ GPS not connected. Check Location Provider settings.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Use phone GPS
      location = await _locationService.getCurrentLocation();
      
      if (location == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to get location. Please enable location services.'),
          ),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoadingLocation = false);
    }
    
    if (location != null && !_hasInitialZoom) {
      _mapController.move(
        LatLng(location.latitude, location.longitude), 15
      );
      _hasInitialZoom = true;
    }
  }
  
  // 🔧 FIX: Unified persistent location stream
  void _startUnifiedLocationStream() {
    // Cancel existing stream if any
    _unifiedLocationSubscription?.cancel();
    
    print('🔄 Starting unified location stream (provider: ${_locationService.currentProvider.name})');
    
    Stream<GeoPoint> locationStream;
    
    if (_locationService.currentProvider == LocationProvider.emlid) {
      // Use Emlid stream
      if (_locationService.isEmlidConnected) {
        locationStream = _locationService.trackEmlidLocation();
        print('📡 Using Emlid location stream');
      } else {
        print('⚠️ Emlid not connected, stream will be empty');
        return;
      }
    } else {
      // Use phone GPS stream
      locationStream = _locationService.trackLocation();
      print('📱 Using phone GPS stream');
    }
    
    // Single stream listener for both blue marker AND tracking
    _unifiedLocationSubscription = locationStream.listen(
      (location) {
        if (mounted) {
          setState(() {
            _currentLocation = location;
          });
          
          // Add to collected points ONLY when tracking and not paused
          if (_isTracking && !_isPaused) {
            setState(() {
              _collectedPoints.add(location);
            });
            // 🔧 NEW: Also save to service for persistence
            _locationService.addTrackingPoint(location);
            print('📍 Point collected: ${_collectedPoints.length} (lat: ${location.latitude.toStringAsFixed(6)})');
          }
        }
      },
      onError: (error) {
        print('❌ Error in unified location stream: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location error: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
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
    // 🔧 FIX: Simplified tracking with proper background support
    
    // Check if using Emlid but not connected
    if (_locationService.currentProvider == LocationProvider.emlid) {
      if (!_locationService.isEmlidConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ GPS not connected! Please connect in Location Provider settings.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }
    
    // 🔧 CRITICAL FIX: Enable background mode for ALL providers
    // For Phone GPS: use background service (Android) or background mode (iOS)
    if (_locationService.currentProvider == LocationProvider.phone) {
      if (Platform.isAndroid) {
        await _locationService.startBackgroundTracking();
      } else if (Platform.isIOS) {
        await _locationService.location.enableBackgroundMode(enable: true);
      }
    }
    // For Emlid GPS: also needs background mode to keep TCP connection alive
    else if (_locationService.currentProvider == LocationProvider.emlid) {
      if (Platform.isAndroid) {
        // Android: Start background service to keep socket alive
        await _locationService.startBackgroundTracking();
        print('🔧 Started background service for Emlid TCP connection');
      } else if (Platform.isIOS) {
        // iOS: Enable background location to keep app active
        await _locationService.location.enableBackgroundMode(enable: true);
        print('🔧 Enabled background mode for Emlid TCP connection');
      }
    }
    
    // 🔧 NEW: Set persistent tracking state in service
    _locationService.startActiveTracking();
    
    setState(() {
      _isTracking = true;
      _isPaused = false;
    });
    
    print('✅ Tracking started (provider: ${_locationService.currentProvider.name})');
    
    final providerName = _locationService.currentProvider == LocationProvider.emlid 
        ? 'RTK GPS' 
        : 'Phone GPS';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📡 Tracking started using $providerName - will continue in background'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _pauseTracking() async {
    // 🔧 FIX: Just set pause flag, stream keeps running
    setState(() => _isPaused = true);
    
    print('⏸️ Tracking paused (stream continues)');
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⏸️ Tracking paused'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _resumeTracking() async {
    // 🔧 FIX: Just clear pause flag, stream already running
    setState(() => _isPaused = false);
    
    print('▶️ Tracking resumed');
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('▶️ Tracking resumed'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _finishTracking() async {
    // 🔧 FIX: Stop background services for ALL providers
    
    // Stop background service/mode for both Phone GPS and Emlid
    if (Platform.isAndroid) {
      await _locationService.stopBackgroundTracking();
      print('🔧 Stopped background service');
    } else if (Platform.isIOS) {
      await _locationService.location.enableBackgroundMode(enable: false);
      print('🔧 Disabled background mode');
    }
    
    // 🔧 NEW: Stop persistent tracking in service
    _locationService.stopActiveTracking();
    
    setState(() {
      _isTracking = false;
      _isPaused = false;
    });
    
    print('⏹️ Tracking finished (stream continues for blue marker)');
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⏹️ Tracking finished'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _addCurrentPoint() async {
    // Untuk point geometry, hanya bisa add 1 point
    if (widget.project.geometryType == GeometryType.point && _collectedPoints.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only 1 point allowed for point geometry'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Ambil koordinat tengah layar
    final center = _mapController.camera.center;
    final centerPoint = GeoPoint(
      latitude: center.latitude,
      longitude: center.longitude,
      timestamp: DateTime.now(),
    );
    
    setState(() {
      _collectedPoints.add(centerPoint);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Point added at center'), duration: Duration(seconds: 1)),
    );
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


  bool _canSaveData() {
    // Validator berdasarkan tipe geometri
    if (widget.project.geometryType == GeometryType.point) {
      return _collectedPoints.length >= 1;  // Point: minimal 1 titik
    } else if (widget.project.geometryType == GeometryType.line) {
      return _collectedPoints.length >= 2;  // Line: minimal 2 titik
    } else if (widget.project.geometryType == GeometryType.polygon) {
      return _collectedPoints.length >= 3;  // Polygon: minimal 3 titik
    }
    return false;
  }

  String _getConfirmTooltip() {
    // Tooltip yang informatif berdasarkan kondisi
    if (_collectedPoints.isEmpty) {
      return 'No points collected';
    }
    
    if (widget.project.geometryType == GeometryType.point) {
      if (_collectedPoints.length >= 1) {
        return 'Save Data';
      }
      return 'Collect 1 point first';
    } else if (widget.project.geometryType == GeometryType.line) {
      if (_collectedPoints.length >= 2) {
        return 'Save Data';
      }
      return 'Need ${2 - _collectedPoints.length} more point(s)';
    } else if (widget.project.geometryType == GeometryType.polygon) {
      if (_collectedPoints.length >= 3) {
        return 'Save Data';
      }
      return 'Need ${3 - _collectedPoints.length} more point(s)';
    }
    return 'Save Data';
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
      // _isFormValid = false;
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
      // Ambil username dari AuthService
      final authService = AuthService();
      final user = await authService.getUser();
      final username = user?.username;

      final geoData = GeoData(
        id: _uuid.v4(),
        projectId: widget.project.id,
        formData: _formData,
        points: _collectedPoints,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        collectedBy: username, // Set username sebagai collectedBy
      );

      await _storageService.saveGeoData(geoData);

      if (mounted) {
        // Reset saving state sebelum pop
        setState(() => _isSaving = false);
        
        // Delay singkat untuk memastikan UI update
        await Future.delayed(const Duration(milliseconds: 100));
        
        if (mounted) {
          // Simpan context sebelum pop untuk SnackBar
          final scaffoldMessenger = ScaffoldMessenger.of(context);
          
          // Pop Form Dialog terlebih dahulu
          Navigator.pop(context);
          await Future.delayed(const Duration(milliseconds: 50));
          
          if (mounted) {
            // Pop DataCollectionScreen dengan result=true untuk trigger reload
            Navigator.pop(context, true);
            
            // Show success message (akan muncul di ProjectDetailScreen)
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('Data saved successfully'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
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

  bool _isOssField(String fieldName) {
    // Exclude fields yang berakhiran _oss_urls, _oss_keys, atau mengandung 'oss'
    final lowerName = fieldName.toLowerCase();
    return lowerName.endsWith('_oss_urls') || 
           lowerName.endsWith('_oss_keys') ||
           lowerName.endsWith('_oss_url') ||
           lowerName.endsWith('_oss_key') ||
           lowerName.contains('_oss_') ||
           lowerName.startsWith('oss_');
  }

  IconData _getGeometryIcon() {
    switch (widget.project.geometryType) {
      case GeometryType.point:
        return Icons.location_on;
      case GeometryType.line:
        return Icons.timeline;
      case GeometryType.polygon:
        return Icons.pentagon_outlined;
    }
  }
  
  String _getLocationProviderName() {
    switch (_locationService.currentProvider) {
      case LocationProvider.phone:
        return 'Phone GPS';
      case LocationProvider.emlid:
        return 'RTK GPS';
    }
  }
  
  IconData _getLocationProviderIcon() {
    switch (_locationService.currentProvider) {
      case LocationProvider.phone:
        return Icons.smartphone;
      case LocationProvider.emlid:
        return Icons.router;
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
        ...data.formData.entries.where((entry) => _isPhotoField(entry.key) && !_isOssField(entry.key)).map((entry) {
                        // Handle PhotoMetadata format
                        List<String> photoPaths = [];
                        
                        if (entry.value is List) {
                          final list = entry.value as List;
                          
                          for (var item in list) {
                            // Handle PhotoMetadata format
                            if (item is Map) {
                              final localPath = item['localPath'];
                              if (localPath != null && localPath.toString().isNotEmpty) {
                                final pathStr = localPath.toString();
                                final file = File(pathStr);
                                if (file.existsSync()) {
                                  photoPaths.add(pathStr);
                                }
                              }
                            }
                            // Handle old string format (backward compatibility)
                            else if (item is String && item.isNotEmpty) {
                              final file = File(item);
                              if (file.existsSync()) {
                                photoPaths.add(item);
                              }
                            }
                          }
                        } else if (entry.value is String && entry.value.toString().isNotEmpty) {
                          final path = entry.value.toString();
                          final file = File(path);
                          if (file.existsSync()) {
                            photoPaths = [path];
                          }
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
                                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.photo_camera,
                                      size: 20,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.key,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        Text(
                                          '${photoPaths.length} photo${photoPaths.length > 1 ? "s" : ""}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Display photos in a grid if multiple
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
                                    final photoPath = photoPaths[index];
                                    final photoFile = File(photoPath);
                                    final fileExists = photoFile.existsSync();
                                    
                                    return GestureDetector(
                                      onTap: () {
                                        if (fileExists) {
                                          _showFullImage(photoPath);
                                        }
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.1),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: fileExists
                                              ? Image.file(
                                                  photoFile,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return _buildImageErrorWidget();
                                                  },
                                                )
                                              : _buildImageNotFoundWidget(photoPath),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              else
                                // Single photo display
                                GestureDetector(
                                  onTap: () {
                                    final photoFile = File(photoPaths[0]);
                                    if (photoFile.existsSync()) {
                                      _showFullImage(photoPaths[0]);
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: () {
                                        final photoFile = File(photoPaths[0]);
                                        final fileExists = photoFile.existsSync();
                                        
                                        if (fileExists) {
                                          return Image.file(
                                            photoFile,
                                            width: double.infinity,
                                            height: 250,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return _buildImageErrorWidget();
                                            },
                                          );
                                        } else {
                                          return _buildImageNotFoundWidget(photoPaths[0]);
                                        }
                                      }(),
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
        if (data.formData.entries.any((entry) => !_isPhotoField(entry.key) && !_isOssField(entry.key))) ...[
          const Row(
            children: [
              Icon(Icons.description_outlined, size: 20, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text('Form Data', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          ...data.formData.entries.where((entry) => !_isPhotoField(entry.key) && !_isOssField(entry.key)).map((entry) {
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

  void _showOfflineDownloadDialog() {
    // Check if basemap is suitable for offline download
    if (_selectedBasemap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a basemap first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_selectedBasemap!.type == BasemapType.pdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF basemaps cannot be downloaded for offline use'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_selectedBasemap!.urlTemplate.isEmpty ||
        _selectedBasemap!.urlTemplate.startsWith('sqlite://') ||
        _selectedBasemap!.urlTemplate.startsWith('overlay://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This basemap does not support offline download'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Get current visible bounds from flutter_map
    final flutterMapBounds = _mapController.camera.visibleBounds;
    
    // Convert flutter_map LatLngBounds to our custom LatLngBounds
    final customBounds = custom_bounds.LatLngBounds(
      northWest: LatLng(
        flutterMapBounds.north,
        flutterMapBounds.west,
      ),
      southEast: LatLng(
        flutterMapBounds.south,
        flutterMapBounds.east,
      ),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => OfflineDownloadDialog(
        visibleBounds: customBounds,
        currentBasemap: _selectedBasemap!,
      ),
    );
  }

  void _showFormBottomSheet() {
    // Initialize form validity based on whether there are required fields
    final hasRequiredFields = widget.project.formFields.any((field) => field.required);
    bool localIsFormValid = !hasRequiredFields;
    bool localIsSaving = false;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            // Local validation function that updates modal state
            void validateFormLocal() {
              bool hasAllRequiredFields = true;
              for (var field in widget.project.formFields) {
                if (field.required) {
                  final value = _formData[field.label];
                  
                  if (value == null) {
                    hasAllRequiredFields = false;
                    break;
                  }
                  
                  if (field.type == FieldType.text || field.type == FieldType.number) {
                    if (value is String && value.trim().isEmpty) {
                      hasAllRequiredFields = false;
                      break;
                    }
                  } else if (field.type == FieldType.photo) {
                    if (value is List && value.isEmpty) {
                      hasAllRequiredFields = false;
                      break;
                    }
                  } else if (field.type == FieldType.checkbox) {
                    if (value is bool && value == false) {
                      hasAllRequiredFields = false;
                      break;
                    }
                  } else if (field.type == FieldType.dropdown || field.type == FieldType.date) {
                    if (value is String && value.isEmpty) {
                      hasAllRequiredFields = false;
                      break;
                    }
                  }
                }
              }
              
              setModalState(() {
                localIsFormValid = hasAllRequiredFields;
              });
            }
            
            return Scaffold(
              appBar: AppBar(
                title: const Text('Survey Data'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(AppTheme.spacingMedium),
                        children: [
                          DynamicForm(
                            formFields: widget.project.formFields,
                            onSaved: (data) => _formData = data,
                            onChanged: () {
                              // Delay check to allow validation to complete
                              Future.delayed(const Duration(milliseconds: 100), () {
                                if (mounted) {
                                  validateFormLocal();
                                }
                              });
                            },
                          ),
                          const SizedBox(height: AppTheme.spacingLarge),
                          
                          // Info card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.primaryColor.withOpacity(0.3),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: AppTheme.primaryColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Fill in all required fields to save your data',
                                    style: TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 100), // Extra space for button
                        ],
                      ),
                    ),
                    // Save Button di Bawah
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: ElevatedButton(
                          onPressed: (localIsSaving || !localIsFormValid) ? null : () async {
                            setModalState(() => localIsSaving = true);
                            
                            // Simpan data
                            await _saveData();
                            
                            // Jika save berhasil, _saveData() akan menutup DataCollectionScreen
                            // dan modal form sheet juga akan tertutup otomatis
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey[300],
                            disabledForegroundColor: Colors.grey[600],
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: localIsSaving
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Saving...',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle_outline, size: 22),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Save Data',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ).then((_) {
      setState(() => _showForm = false);
    });
  }

  List<Widget> _buildBasemapLayers(Basemap basemap) {
    // Check if this is an overlay-mode PDF basemap
    if (basemap.useOverlayMode && 
        basemap.pdfOverlayImagePath != null &&
        basemap.hasPdfGeoreferencing) {
      
      //print('⚡ Using Overlay Mode for ${basemap.name}');
      
      // VALIDASI: Cek apakah file image ada
      final imageFile = File(basemap.pdfOverlayImagePath!);
      if (!imageFile.existsSync()) {
        //print('❌ ERROR: Image file not found at: ${basemap.pdfOverlayImagePath}');
        // Fallback ke OSM jika file tidak ada
        return [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: ApiConfig.bundleName,
          ),
        ];
      }
      
     
      
      // VALIDASI: Cek bounds tidak null
      if (basemap.pdfMinLat == null || basemap.pdfMinLon == null ||
          basemap.pdfMaxLat == null || basemap.pdfMaxLon == null) {
        //print('❌ ERROR: Invalid bounds (null values)');
        return [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: ApiConfig.bundleName,
          ),
        ];
      }
      
      // VALIDASI: Cek min < max untuk latitude dan longitude
      if (basemap.pdfMinLat! >= basemap.pdfMaxLat! || 
          basemap.pdfMinLon! >= basemap.pdfMaxLon!) {
        print('❌ ERROR: Invalid bounds (min >= max)');
        print('   MinLat (${basemap.pdfMinLat}) should be < MaxLat (${basemap.pdfMaxLat})');
        print('   MinLon (${basemap.pdfMinLon}) should be < MaxLon (${basemap.pdfMaxLon})');
        return [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: ApiConfig.bundleName,
          ),
        ];
      }
      
      try {
        // Use OverlayImageLayer for PDF overlay mode (FAST!)
        print('✅ Creating OverlayImageLayer...');
        
        // FIX: LatLngBounds constructor order is (southwest, northeast)
        final bounds = LatLngBounds(
          LatLng(basemap.pdfMinLat!, basemap.pdfMinLon!),  // southwest corner (minLat, minLon)
          LatLng(basemap.pdfMaxLat!, basemap.pdfMaxLon!),  // northeast corner (maxLat, maxLon)
        );
        
        print('✅ Bounds created successfully');
        print('   Southwest corner: ${bounds.southWest}');
        print('   Northeast corner: ${bounds.northEast}');
        print('📷 Current map center: ${_mapController.camera.center}');
        print('📷 Current map zoom: ${_mapController.camera.zoom}');
        
        // Cek apakah image bisa di-decode
        try {
          final bytes = imageFile.readAsBytesSync();
          print('🖼️ Image bytes read: ${bytes.length}');
          print('🖼️ First bytes: ${bytes.take(20).toList()}');
        } catch (e) {
          print('❌ Error reading image bytes: $e');
        }
        
        return [
          // Base layer OSM (optional, untuk konteks)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: ApiConfig.bundleName,
            tileProvider: NetworkTileProvider(),
          ),
          // PDF Overlay layer
          OverlayImageLayer(
            overlayImages: [
              OverlayImage(
                bounds: bounds,
                imageProvider: FileImage(imageFile),
                opacity: 1.0,  // Full opacity untuk PDF map
                gaplessPlayback: true,
              ),
            ],
          ),
        ];
      } catch (e, stackTrace) {
        print('❌ ERROR creating OverlayImageLayer: $e');
        print('Stack trace: $stackTrace');
        
        // Fallback ke OSM
        return [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: ApiConfig.bundleName,
          ),
        ];
      }
    } else {
      // Use TileLayer for TMS or tile-based PDF basemaps
      //print('🗺️ Using TileLayer for ${basemap.name}');
      
      return [
        TileLayer(
          urlTemplate: basemap.urlTemplate.startsWith('sqlite://') || basemap.urlTemplate.startsWith('overlay://')
              ? '' // PDF basemap from SQLite or overlay - URL not used
              : basemap.urlTemplate, // TMS basemap URL
          userAgentPackageName: ApiConfig.bundleName,
          minZoom: basemap.minZoom.toDouble(),
          maxZoom: basemap.maxZoom.toDouble(),
          tileProvider: SqliteCachedTileProvider(
            basemapId: basemap.id,
            maxStale: const Duration(days: 30),
          ),
        ),
      ];
    }
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
              color: Colors.orange.withOpacity(0.7),
              strokeWidth: 3,
            ),
          ],
        ));
      } else if (widget.project.geometryType == GeometryType.polygon) {
        if (data.points.length >= 3) {
          layers.add(PolygonLayer(
            polygons: [
              Polygon(
                points: data.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                color: Colors.orange.withOpacity(0.15),
                borderColor: Colors.orange.withOpacity(0.7),
                borderStrokeWidth: 3,
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
              width: 25,
              height: 25,
              child: GestureDetector(
                onTap: () => _onExistingDataTap(data),
                child: Container(
                  width: 23,
                  height: 23,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
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
                    size: 20,
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
              width: 25,
              height: 25,
              child: GestureDetector(
                onTap: () => _onExistingDataTap(data),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black87, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.info,
                    color: Colors.black87,
                    size: 20,
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
              width: 25,
              height: 25,
              child: GestureDetector(
                onTap: () => _onExistingDataTap(data),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black87, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.info,
                    color: Colors.black87,
                    size: 20,
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        clipBehavior: Clip.none, // Agar shadow tidak terpotong
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getGeometryIcon(),
                size: 18,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                widget.project.geometryType.toString().split('.').last.toUpperCase(),
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          // Connectivity Indicator (Status)
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.grey.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: const Center(
              child: ConnectivityIndicator(
                showLabel: false,
                iconSize: 20,
              ),
            ),
          ),
          // Location Provider Button
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                _locationService.currentProvider == LocationProvider.emlid
                    ? Icons.satellite_alt
                    : Icons.gps_fixed,
                size: 20,
                color: _locationService.currentProvider == LocationProvider.emlid
                    ? (_locationService.isEmlidConnected && _locationService.isEmlidStreaming
                        ? Colors.blue
                        : Colors.orange)
                    : Colors.black87,
              ),
              padding: EdgeInsets.zero,
              tooltip: 'Location Provider Settings',
              onPressed: () async {
                // Navigate to Location Provider screen
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LocationProviderScreen(),
                  ),
                );
                
                // Reload if provider changed
                if (result == true && mounted) {
                  // Restart location stream with new provider
                  _startUnifiedLocationStream();
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Location provider updated to ${_locationService.currentProvider.name}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
          // Save/Loading Button
          if (_isSaving)
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                ),
              ),
            )
          else
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _canSaveData() 
                    ? Colors.green      // Hijau jika memenuhi syarat
                    : Colors.grey[300], // Abu-abu jika belum memenuhi syarat
                borderRadius: BorderRadius.circular(12),
                boxShadow: _canSaveData()
                    ? [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.green.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],  // Tidak ada shadow jika disabled
              ),
              child: IconButton(
                icon: Icon(
                  Icons.check, 
                  size: 20, 
                  color: _canSaveData()
                      ? Colors.white      // Putih jika enabled
                      : Colors.grey[600], // Abu-abu tua jika disabled
                ),
                padding: EdgeInsets.zero,
                onPressed: _canSaveData() ? () {
                  setState(() => _showForm = true);
                  _showFormBottomSheet();
                } : null,
                tooltip: _getConfirmTooltip(),
              ),
            ),
        ],
      ),
      body: Stack(
          children: [
            _buildMap(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Transform.translate(
                offset: Offset(0, 0),
                child: _buildBottomControls(),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        // Clip map untuk menghilangkan celah putih di bawah
        Positioned.fill(
          bottom: 0, // Extend map sedikit ke bawah untuk menutupi celah
          child: ClipRect(
            child: Builder(
          builder: (context) {
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
            
            return ClipRect(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _selectedBasemap?.type == BasemapType.pdf && _selectedBasemap!.hasPdfGeoreferencing
                      ? LatLng(
                          (_selectedBasemap!.pdfMinLat! + _selectedBasemap!.pdfMaxLat!) / 2,
                          (_selectedBasemap!.pdfMinLon! + _selectedBasemap!.pdfMaxLon!) / 2,
                        )
                      : (_currentLocation != null
                          ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
                          : const LatLng(-6.2088, 106.8456)),
                  initialZoom: _selectedBasemap?.type == BasemapType.pdf && _selectedBasemap!.hasPdfGeoreferencing
                      ? 13  // PDF basemap: zoom level yang reasonable
                      : 15,  // Non-PDF: zoom lebih tinggi ke user location
                  onTap: _onMapTap,
                  onPositionChanged: (position, hasGesture) {
                    setState(() {
                      _centerCoordinates = position.center!;
                    });
                  },
                ),
              children: [
                // Basemap Layer - Support both Tile and Overlay modes
                if (_selectedBasemap != null) ..._buildBasemapLayers(_selectedBasemap!)
                else
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: ApiConfig.bundleName,
                    tileProvider: SqliteCachedTileProvider(
                      basemapId: 'osm_road',
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
                                ? _settingsService.settings.lineColor
                                : _settingsService.settings.polygonColor,
                            strokeWidth: _settingsService.settings.lineWidth,
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
                            color: _settingsService.settings.polygonColor.withOpacity(_settingsService.settings.polygonOpacity),
                            borderColor: _settingsService.settings.polygonColor,
                            borderStrokeWidth: _settingsService.settings.lineWidth,
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
                          width: _settingsService.settings.pointSize * 2,
                          height: _settingsService.settings.pointSize * 2,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _settingsService.settings.pointColor,
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
                            width: _settingsService.settings.pointSize * 2,
                            height: _settingsService.settings.pointSize * 2,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red, // Last point tetap merah untuk dibedakan
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
                
                // Current Location Marker (User Location - Blue with direction)
                if (_currentLocation != null && !_isTracking)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          _currentLocation!.latitude,
                          _currentLocation!.longitude,
                        ),
                        width: 60,
                        height: 60,
                        child: UserLocationMarker(
                          bearing: _currentBearing,
                          isEmlidGPS: _locationService.currentProvider == LocationProvider.emlid,
                        ),
                      ),
                    ],
                  ),
              ],
              ),
            );
          },
          ),
        ),
        ),
        
        // Center Crosshair Marker dengan koordinat (hanya muncul setelah loading selesai)
        if (!_isLoadingLocation)
          const Center(
            child: IgnorePointer(
              child: Padding(
                      padding: EdgeInsets.only(top: 0), // geser ke bawah 16px
                      child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Koordinat display
                  // Container(
                  //   margin: const EdgeInsets.only(bottom: 8),
                  //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  //   decoration: BoxDecoration(
                  //     color: Colors.black87,
                  //     borderRadius: BorderRadius.circular(8),
                  //     boxShadow: [
                  //       BoxShadow(
                  //         color: Colors.black.withOpacity(0.3),
                  //         blurRadius: 4,
                  //         offset: const Offset(0, 2),
                  //       ),
                  //     ],
                  //   ),
                  //   child: Text(
                  //     '${_centerCoordinates.latitude.toStringAsFixed(6)}, ${_centerCoordinates.longitude.toStringAsFixed(6)}',
                  //     style: const TextStyle(
                  //       color: Colors.white,
                  //       fontSize: 11,
                  //       fontWeight: FontWeight.w500,
                  //       fontFamily: 'monospace',
                  //     ),
                  //   ),
                  // ),


                  // Crosshair icon
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.location_searching,
                      size: 40,
                      color: Colors.black87,
                    ),
                  ),
                      
                ],
                )
              ),
            ),
          ),
        
       
        
        // Info Card Overlay (dengan padding top untuk status bar dan app bar)
        Positioned(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + AppTheme.spacingSmall,
          left: AppTheme.spacingMedium,
          right: AppTheme.spacingMedium,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoCard(),
              const SizedBox(height: 4),
              // Koordinat Crosshair
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.gps_fixed,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_centerCoordinates.latitude.toStringAsFixed(6)}, ${_centerCoordinates.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Zoom to User Location Button
        Positioned(
          bottom: _isBottomSheetExpanded 
              ? AppTheme.spacingLarge + 320  // Expanded: adjust upward
              : AppTheme.spacingLarge + 50,   // Collapsed: normal position
          right: AppTheme.spacingMedium,
          child: FloatingActionButton(
            heroTag: 'userLocation',
            mini: true,
            backgroundColor: Colors.white,
            elevation: 6,
            child: const Icon(Icons.my_location, color: AppTheme.primaryColor),
            onPressed: () {
              if (_currentLocation != null) {
                _mapController.move(
                  LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
                  17,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Zoomed to your location'),
                    duration: Duration(seconds: 1),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Location not available'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ),
        
        // Basemap Selector Button
        Positioned(
          bottom: _isBottomSheetExpanded 
              ? AppTheme.spacingLarge + 380  // Expanded: adjust upward
              : AppTheme.spacingLarge + 110,  // Collapsed: normal position
          right: AppTheme.spacingMedium,
          child: FloatingActionButton(
            heroTag: 'basemap',
            mini: true,
            backgroundColor: Colors.white,
            elevation: 6,
            child: const Icon(Icons.layers, color: AppTheme.primaryColor),
            onPressed: _showBasemapSelector,
          ),
        ),
        
        // Offline Download Button
        Positioned(
          bottom: _isBottomSheetExpanded 
              ? AppTheme.spacingLarge + 440  // Expanded: adjust upward
              : AppTheme.spacingLarge + 170,  // Collapsed: normal position
          right: AppTheme.spacingMedium,
          child: FloatingActionButton(
            heroTag: 'offline_download',
            mini: true,
            backgroundColor: Colors.white,
            elevation: 6,
            child: const Icon(Icons.download, color: Colors.green),
            tooltip: 'Download for Offline',
            onPressed: _showOfflineDownloadDialog,
          ),
        ),
        
        
        // Mode Toggle Button (only for line/polygon)
        if (widget.project.geometryType != GeometryType.point)
          Positioned(
            bottom: _isBottomSheetExpanded 
                ? AppTheme.spacingLarge + 500  // Expanded: adjust upward
                : AppTheme.spacingLarge + 230,  // Collapsed: normal position
            right: AppTheme.spacingMedium,
            child: FloatingActionButton(
              heroTag: 'mode',
              mini: true,
              backgroundColor: _collectionMode == CollectionMode.drawing
                  ? AppTheme.primaryColor
                  : Colors.white,
              elevation: 6,
              child: Icon(
                _collectionMode == CollectionMode.drawing ? Icons.touch_app : Icons.edit,
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
          )
        
      ]
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
      color: Colors.white.withOpacity(0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Baris pertama: Status tracking dan jumlah points
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
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _collectionMode == CollectionMode.drawing 
                      ? 'Drawing Mode' 
                      : _isTracking 
                        ? (_isPaused ? 'Paused' : 'Tracking')
                        : 'Inactive',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_collectedPoints.length} pts',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            
            // Baris kedua: Location provider dan metric (distance/area)
            const SizedBox(height: 6),
            Row(
              children: [
                // Location Provider
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _locationService.currentProvider == LocationProvider.emlid
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _locationService.currentProvider == LocationProvider.emlid
                          ? Colors.blue.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getLocationProviderIcon(),
                        size: 10,
                        color: _locationService.currentProvider == LocationProvider.emlid
                            ? Colors.blue[700]
                            : Colors.grey[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _locationService.currentProvider == LocationProvider.emlid ? 'RTK' : 'GPS',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: _locationService.currentProvider == LocationProvider.emlid
                              ? Colors.blue[700]
                              : Colors.grey[700],
                        ),
                      ),
                      // Warning indicator if Emlid but not streaming
                      if (_locationService.currentProvider == LocationProvider.emlid &&
                          (!_locationService.isEmlidConnected || !_locationService.isEmlidStreaming)) ...[
                        const SizedBox(width: 3),
                        Icon(
                          Icons.warning_rounded,
                          size: 10,
                          color: Colors.orange[700],
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Distance or Area
                if (distance != null)
                  Expanded(
                    child: Text(
                      '📏 ${_settingsService.settings.formatDistance(distance)}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  )
                else if (area != null)
                  Expanded(
                    child: Text(
                      '📐 ${_settingsService.settings.formatArea(area)}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  )
                else
                  const Spacer(),
                
                // Accuracy and Fix Quality
                if (_currentLocation != null) ...[
                  Text(
                    '±${_currentLocation!.accuracy?.toStringAsFixed(1) ?? 'N/A'}m',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                  // Show fix quality for Emlid
                  if (_locationService.currentProvider == LocationProvider.emlid &&
                      _currentLocation!.fixQuality != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getFixQualityColor(_currentLocation!.fixQuality!),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        _currentLocation!.fixQuality!.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
            
            // Drawing mode hint
            if (_collectionMode == CollectionMode.drawing) ...[
              const SizedBox(height: 4),
              Text(
                'Tap on map to add points',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Color _getFixQualityColor(String fixQuality) {
    switch (fixQuality.toLowerCase()) {
      case 'fix':
        return Colors.green;
      case 'float':
        return Colors.orange;
      case 'autonomous':
      case 'dgps':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildImageErrorWidget() {
    return Container(
      height: 250,
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load image',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The image file may be corrupted',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageNotFoundWidget(String path) {
    return Container(
      height: 250,
      color: Colors.orange[50],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_not_supported_rounded,
                size: 64,
                color: Colors.orange[400],
              ),
              const SizedBox(height: 12),
              Text(
                'Image file not found',
                style: TextStyle(
                  color: Colors.orange[800],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                path,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return CollapsibleBottomControls(
      isExpanded: _isBottomSheetExpanded,
      onToggleExpanded: () {
        setState(() {
          _isBottomSheetExpanded = !_isBottomSheetExpanded;
        });
      },
      geometryType: widget.project.geometryType,
      collectionMode: _collectionMode,
      isTracking: _isTracking,
      isPaused: _isPaused,
      collectedPoints: _collectedPoints,
      onToggleTracking: _toggleTracking,
      onTogglePause: _togglePause,
      onAddPoint: _addCurrentPoint,
      onUndoPoint: _undoLastPoint,
      onClearPoints: _clearPoints,
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
