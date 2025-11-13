import 'package:flutter/material.dart';
import 'package:geoform_app/theme/app_theme.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import '../../models/project_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/form_field_model.dart';
import '../../services/storage_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/sync_service.dart';
import '../../services/api_service.dart';
import '../../config/api_config.dart';
import '../data_collection/data_collection_screen.dart';
import 'edit_geo_data_screen.dart';
import 'create_project_screen.dart';
import '../../widgets/geo_data_list_item.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import 'dart:convert';
import 'dart:async';

class ProjectDetailScreen extends StatefulWidget {
  final Project project;

  const ProjectDetailScreen({Key? key, required this.project}) : super(key: key);

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final StorageService _storageService = StorageService();
  final ConnectivityService _connectivityService = ConnectivityService();
  final SyncService _syncService = SyncService();
  final ApiService _apiService = ApiService();
  
  List<GeoData> _geoDataList = [];
  List<GeoData> _filteredGeoDataList = [];
  bool _isLoading = true;
  late Project _currentProject;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isOnline = false;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isSyncing = false;
  final ScrollController _scrollController = ScrollController();
  String _syncProgress = '';
  int _totalPhotosToProcess = 0;
  int _processedPhotos = 0;

  @override
  void initState() {
    super.initState();
    _currentProject = widget.project;
    _loadGeoData();
    _searchController.addListener(_filterGeoData);
    _initConnectivity();
    _scrollController.addListener(_onScroll);
  }

  void _initConnectivity() {
    _connectivityService.startMonitoring();
    _isOnline = _connectivityService.isOnline;
    _connectivitySubscription = _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  void _onScroll() {
    // Reserved for future scroll-based actions
  }

  Color _getGeoColor(String polygonType) {
    if (polygonType == 'POLYGON') {
      return AppTheme.polygonColor;
    }
    if (polygonType == 'LINE') {
      return AppTheme.lineColor;
    }
    if (polygonType == 'POINT') {
      return AppTheme.pointColor;
    }

    return Colors.grey;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _connectivitySubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _filterGeoData() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredGeoDataList = _geoDataList;
      } else {
        _filteredGeoDataList = _geoDataList.where((data) {
          // Search in form data values
          final formDataMatch = data.formData.entries.any((entry) {
            return entry.value.toString().toLowerCase().contains(query);
          });
          // Search in date
          final dateMatch = _formatDate(data.createdAt).toLowerCase().contains(query);
          return formDataMatch || dateMatch;
        }).toList();
      }
    });
  }

  Future<void> _loadGeoData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _storageService.loadGeoData(_currentProject.id);
      setState(() {
        _geoDataList = data;
        _filteredGeoDataList = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  /// Sync GeoData untuk project ini dari server
  Future<void> _syncGeoDataFromServer() async {
    if (_isSyncing || !_isOnline) return;

    setState(() {
      _isSyncing = true;
      _syncProgress = 'Fetching data from server...';
    });

    try {
      // Fetch geodata from server
      final geoDataResponse = await _apiService.get(
        '${ApiConfig.syncDataEndpoint}by-project/?project_id=${_currentProject.id}',
      );

      int newGeoDataCount = 0;
      int updatedGeoDataCount = 0;

      if (_apiService.isSuccess(geoDataResponse)) {
        final geoDataList = jsonDecode(geoDataResponse.body);
        
        // Load existing geodata
        final existingGeoData = await _storageService.loadGeoData(_currentProject.id);
        final existingGeoDataMap = {for (var g in existingGeoData) g.id: g};

        // Process geodata dari server
        if (geoDataList is List && geoDataList.isNotEmpty) {
          setState(() {
            _syncProgress = 'Processing ${geoDataList.length} records...';
          });

          for (var i = 0; i < geoDataList.length; i++) {
            try {
              final geoDataJson = geoDataList[i];
              setState(() {
                _syncProgress = 'Processing record ${i + 1}/${geoDataList.length}...';
              });

              final serverGeoData = GeoData.fromJson(geoDataJson);
              final existingGeoData = existingGeoDataMap[serverGeoData.id];

              if (existingGeoData == null) {
                // GeoData baru dari server - download photos
                setState(() {
                  _syncProgress = 'Downloading photos for record ${i + 1}...';
                });
                
                // Process photos (download from OSS)
                final processedFormData = await _syncService.processFormDataForPull(
                  serverGeoData.formData,
                  _currentProject,
                );
                
                final updatedGeoData = serverGeoData.copyWith(formData: processedFormData);
                await _storageService.saveGeoData(updatedGeoData);
                newGeoDataCount++;
              } else if (serverGeoData.updatedAt.isAfter(existingGeoData.updatedAt)) {
                // Update geodata yang lebih baru dari server
                setState(() {
                  _syncProgress = 'Updating record ${i + 1}...';
                });
                
                // Process photos (download from OSS)
                final processedFormData = await _syncService.processFormDataForPull(
                  serverGeoData.formData,
                  _currentProject,
                );
                
                final updatedGeoData = serverGeoData.copyWith(formData: processedFormData);
                await _storageService.saveGeoData(updatedGeoData);
                updatedGeoDataCount++;
              }
            } catch (e) {
              print('Error processing geodata from server: $e');
            }
          }
        }
      }

      // Reload local data
      await _loadGeoData();

      // Show notification jika ada data baru
      if (mounted && (newGeoDataCount > 0 || updatedGeoDataCount > 0)) {
        String message = '';
        if (newGeoDataCount > 0) {
          message += '$newGeoDataCount new';
        }
        if (updatedGeoDataCount > 0) {
          if (message.isNotEmpty) message += ', ';
          message += '$updatedGeoDataCount updated';
        }
        message += ' geodata synced';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_download, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error syncing geodata from server: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Sync error: $e')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgress = '';
        });
      }
    }
  }

  Future<void> _editProject() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateProjectScreen(project: _currentProject),
      ),
    );

    if (result == true) {
      final projects = await _storageService.loadProjects();
      final updatedProject = projects.firstWhere((p) => p.id == _currentProject.id);
      setState(() {
        _currentProject = updatedProject;
      });
    }
  }

  /// Convert GeoData to GeoJSON Feature Collection
  Map<String, dynamic> _exportAsGeoJSON() {
    List<Map<String, dynamic>> features = [];
    
    for (var geoData in _geoDataList) {
      // Determine geometry type and coordinates based on project geometry type
      String geometryType;
      dynamic coordinates;
      
      if (_currentProject.geometryType == GeometryType.point) {
        geometryType = 'Point';
        if (geoData.points.isNotEmpty) {
          final point = geoData.points.first;
          coordinates = [point.longitude, point.latitude];
          if (point.altitude != null) {
            coordinates.add(point.altitude);
          }
        } else {
          coordinates = [0.0, 0.0]; // Default jika tidak ada point
        }
      } else if (_currentProject.geometryType == GeometryType.line) {
        geometryType = 'LineString';
        coordinates = geoData.points.map((point) {
          List<double> coord = [point.longitude, point.latitude];
          if (point.altitude != null) {
            coord.add(point.altitude!);
          }
          return coord;
        }).toList();
      } else { // Polygon
        geometryType = 'Polygon';
        // GeoJSON Polygon requires array of LinearRings (first is exterior, rest are holes)
        // Each LinearRing must be closed (first point = last point)
        List<List<double>> ring = geoData.points.map((point) {
          List<double> coord = [point.longitude, point.latitude];
          if (point.altitude != null) {
            coord.add(point.altitude!);
          }
          return coord;
        }).toList();
        
        // Close the ring if not already closed
        if (ring.isNotEmpty && ring.first != ring.last) {
          ring.add(ring.first);
        }
        
        coordinates = [ring]; // Wrap in array for Polygon format
      }
      
      // Create properties from formData
      Map<String, dynamic> properties = {
        'id': geoData.id,
        'createdAt': geoData.createdAt.toIso8601String(),
        'updatedAt': geoData.updatedAt.toIso8601String(),
        'isSynced': geoData.isSynced,
      };
      
      // Add form data to properties
      properties.addAll(geoData.formData);
      
      // Create GeoJSON feature
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': geometryType,
          'coordinates': coordinates,
        },
        'properties': properties,
      });
    }
    
    // Create GeoJSON Feature Collection
    return {
      'type': 'FeatureCollection',
      'name': _currentProject.name,
      'crs': {
        'type': 'name',
        'properties': {
          'name': 'urn:ogc:def:crs:OGC:1.3:CRS84'
        }
      },
      'features': features,
    };
  }

  Future<void> _exportData() async {
    try {
      // Export as GeoJSON Feature Collection
      final geoJsonData = _exportAsGeoJSON();
      final jsonString = const JsonEncoder.withIndent('  ').convert(geoJsonData);
      
      // Show export dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.file_download, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Text('Export as GeoJSON'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Format: GeoJSON Feature Collection',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Features: ${_geoDataList.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonString,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: jsonString));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('GeoJSON copied to clipboard'),
                                ],
                              ),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _downloadGeoJSON(jsonString);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                  ),
                ),
              ],
            ),
          ),
        );

      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting data: $e')),
        );
      }
    }
  }

  Future<void> _downloadGeoJSON(String jsonString) async {
    try {
      // Generate filename with project name and timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final projectName = _currentProject.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
      final filename = '${projectName}_$timestamp.geojson';

      // Get download directory
      Directory? directory;
      if (Platform.isAndroid) {
        // Try multiple directories for Android
        final downloadDir = Directory('/storage/emulated/0/Download');
        
        if (await downloadDir.exists()) {
          directory = downloadDir;
        } else {
          // Fallback to app-specific external storage (no permission required)
          directory = await getExternalStorageDirectory();
          
          // Create GeoJSON folder in app directory
          if (directory != null) {
            final geoJsonDir = Directory('${directory.path}/GeoJSON');
            if (!await geoJsonDir.exists()) {
              await geoJsonDir.create(recursive: true);
            }
            directory = geoJsonDir;
          }
        }
      } else if (Platform.isIOS) {
        // For iOS, use documents directory
        directory = await getApplicationDocumentsDirectory();
      } else {
        // For other platforms
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception('Could not access storage directory');
      }

      // Create file path
      final filePath = '${directory.path}/$filename';
      final file = File(filePath);

      // Write GeoJSON to file
      await file.writeAsString(jsonString);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'GeoJSON downloaded successfully!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Saved to: $filePath',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error saving file: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _syncProject() async {
    // Check if online
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 8),
              Text('No internet connection. Please connect to sync project.'),
            ],
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Project'),
        content: Text('Sync project "${_currentProject.name}" to server?\n\nThis will upload project structure and form fields.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sync'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loading
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Syncing project to server...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      // Sync project to backend
      final result = await _syncService.syncProject(_currentProject);
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        if (result.success) {
          // Update project sync status if needed
          final updatedProject = _currentProject.copyWith(
            updatedAt: DateTime.now(),
          );
          await _storageService.saveProject(updatedProject);
          
          setState(() {
            _currentProject = updatedProject;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(result.message),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // Show error dialog
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Sync Failed'),
                ],
              ),
              content: Text(result.message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error syncing project: $e')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _syncAllData() async {
    // Check if online
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 8),
              Text('No internet connection. Please connect to sync data.'),
            ],
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final unsyncedData = _geoDataList.where((data) => !data.isSynced).toList();
    
    if (unsyncedData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All data is already synced')),
      );
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Data'),
        content: Text('Sync ${unsyncedData.length} record${unsyncedData.length > 1 ? "s" : ""} to server?\n\nThis will upload photos to cloud storage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sync'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Set syncing state
    setState(() {
      _isSyncing = true;
      _syncProgress = 'Preparing to upload...';
    });

    try {
      int successCount = 0;
      List<String> errors = [];
      
      // Sync each unsynced data to backend
      for (var i = 0; i < unsyncedData.length; i++) {
        final data = unsyncedData[i];
        
        setState(() {
          _syncProgress = 'Uploading record ${i + 1}/${unsyncedData.length}...';
        });
        
        final result = await _syncService.syncGeoData(data, _currentProject);
        
        if (result.success) {
          successCount++;
        } else {
          errors.add(result.message);
        }
      }

      // Reload data
      await _loadGeoData();

      if (mounted) {
        
        if (successCount == unsyncedData.length) {
          // All synced successfully
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$successCount record${successCount > 1 ? "s" : ""} synced successfully',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else if (successCount > 0) {
          // Partial success
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Partial Sync'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$successCount of ${unsyncedData.length} records synced.'),
                    const SizedBox(height: 12),
                    const Text(
                      'Errors:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...errors.take(5).map((error) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $error',
                        style: const TextStyle(fontSize: 12),
                      ),
                    )),
                    if (errors.length > 5)
                      Text('... and ${errors.length - 5} more errors'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          // All failed
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Sync Failed'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Failed to sync data to server.'),
                    const SizedBox(height: 12),
                    const Text(
                      'Errors:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...errors.take(5).map((error) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $error',
                        style: const TextStyle(fontSize: 12),
                      ),
                    )),
                    if (errors.length > 5)
                      Text('... and ${errors.length - 5} more errors'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error syncing data: $e')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgress = '';
        });
      }
    }
  }

  Future<void> _deleteGeoData(GeoData data) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Data'),
        content: const Text('Are you sure you want to delete this data?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _storageService.deleteGeoData(data.id);
        _loadGeoData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting data: $e')),
          );
        }
      }
    }
  }

  Future<void> _editGeoData(GeoData data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditGeoDataScreen(
          geoData: data,
          project: _currentProject,
        ),
      ),
    );

    // Reload data jika ada perubahan
    if (result == true) {
      await _loadGeoData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.black45),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                  hintText: 'Search data...',
                  hintStyle: TextStyle(color: Colors.black45),
                  border: InputBorder.none,
                ),
              )
            : Row(
                children: [
                  Expanded(child: Text(_currentProject.name)),
                  const ConnectivityIndicator(
                    showLabel: true,
                    iconSize: 16,
                  ),
                ],
              ),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _isSearching = false;
                  _filteredGeoDataList = _geoDataList;
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 8,
            offset: const Offset(0, 50),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'pull_from_server',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.cloud_download_rounded,
                        color: Colors.green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pull from Server',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Download geodata from cloud',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'sync_to_server',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.cloud_upload_rounded,
                        color: Theme.of(context).primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Push to Server',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Upload geodata to cloud',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'info',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Project Info',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'View project details',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'pull_from_server') {
                _syncGeoDataFromServer();
              } else if (value == 'sync_to_server') {
                _syncAllData();
              } else if (value == 'info') {
                _showProjectInfo();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Sync Indicator
          if (_isSyncing)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.blue[50],
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _syncProgress.isEmpty ? 'Syncing with server...' : _syncProgress,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[800],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          
          // Stats Card
          _buildStatsCard(),
          
          // Data List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _geoDataList.isEmpty
                    ? _buildEmptyState()
                    : _filteredGeoDataList.isEmpty
                        ? _buildNoResultsState()
                        : RefreshIndicator(
                            onRefresh: () async {
                              // Saat pull to refresh, sync geodata dari server
                              if (_isOnline) {
                                await _syncGeoDataFromServer();
                              } else {
                                await _loadGeoData();
                              }
                            },
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 16,
                                top: 16,
                                bottom: 80, // Padding untuk FAB
                              ),
                              itemCount: _filteredGeoDataList.length,
                              itemBuilder: (context, index) {
                                final data = _filteredGeoDataList[index];
                                return GeoDataListItem(
                                  geoData: data,
                                  geometryType: _currentProject.geometryType,
                                  project: _currentProject,
                                  onDelete: () => _deleteGeoData(data),
                                  onEdit: () => _editGeoData(data),
                                  onTap: () => _showDataDetail(data),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToDataCollection,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 6,
        child: const Icon(Icons.add_location),
        
      ),
    );
  }

  Widget _buildStatsCard() {
    final unsyncedCount = _geoDataList.where((data) => !data.isSynced).length;
    
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  icon: _getGeometryIconForType(),
                  label: 'Type',
                  value: _currentProject.geometryType.toString().split('.').last.toUpperCase(),
                  color: _getGeoColor(_currentProject.geometryType.toString().split('.').last.toUpperCase()),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: Colors.grey[300],
                ),
                _buildStatItem(
                  icon: Icons.storage_rounded,
                  label: 'Records',
                  value: '${_geoDataList.length}',
                  color: Colors.grey,
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: Colors.grey[300],
                ),
                _buildStatItem(
                  icon: Icons.view_list_rounded,
                  label: 'Fields',
                  value: '${_currentProject.formFields.length}',
                  color: Colors.orange,
                ),
              ],
            ),
          ),
          if (unsyncedCount > 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_upload, size: 18, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Text(
                    '$unsyncedCount ${unsyncedCount == 1 ? "record" : "records"} not synced',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[800],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isOnline ? _syncAllData : null,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Sync Now',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _isOnline ? Colors.orange[800] : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.sync, size: 16, color: _isOnline ? Colors.orange[800] : Colors.grey),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getGeometryIconForType() {
    switch (_currentProject.geometryType) {
      case GeometryType.point:
        return Icons.place_rounded;
      case GeometryType.line:
        return Icons.timeline_rounded;
      case GeometryType.polygon:
        return Icons.pentagon_outlined;
    }
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 22,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Data Collected Yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start collecting geospatial data for this project',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Results Found',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  void _navigateToDataCollection() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DataCollectionScreen(project: _currentProject),
      ),
    );

    // Reload data jika ada perubahan (data baru ditambahkan)
    if (result == true) {
      print('Data collection result: true, reloading data...');
      await _loadGeoData();
      
      // Scroll ke atas untuk melihat data terbaru
      if (_geoDataList.isNotEmpty && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _showProjectInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_currentProject.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Description',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(_currentProject.description),
              const SizedBox(height: 16),
              Text(
                'Geometry Type',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(_currentProject.geometryType.toString().split('.').last.toUpperCase()),
              const SizedBox(height: 16),
              Text(
                'Form Fields',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ..._currentProject.formFields.map((field) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${field.label} (${field.type.toString().split('.').last})'),
                  )),
              const SizedBox(height: 16),
              Text(
                'Created',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(_formatDate(_currentProject.createdAt)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
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
              // Header
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withOpacity(0.9),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
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
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo Section
                      ...data.formData.entries.where((entry) => _isPhotoField(entry.key) && !_isOssField(entry.key)).map((entry) {
                        // Handle both List and String types - hanya ambil local paths
                        List<String> photoPaths = [];
                        
                        // Helper function to check if a path is local
                        bool isLocalPath(String path) {
                          final lowerPath = path.toLowerCase();
                          // Check if it's NOT a URL or OSS key
                          return !lowerPath.startsWith('http://') && 
                                 !lowerPath.startsWith('https://') &&
                                 !lowerPath.contains('aliyuncs.com') &&
                                 !lowerPath.startsWith('oss-') &&
                                 // Tambahan: pastikan path seperti file system path
                                 (lowerPath.contains('/') || lowerPath.contains('\\'));
                        }
                        
                        if (entry.value is List) {
                          final list = entry.value as List;
                          
                          for (var item in list) {
                            // Handle if item is a Map (e.g., {local_path: ..., oss_url: ..., oss_key: ...})
                            if (item is Map) {
                              // Try to get local_path or localPath key
                              final localPath = item['local_path'] ?? item['localPath'] ?? item['path'];
                              if (localPath != null && localPath.toString().isNotEmpty) {
                                final pathStr = localPath.toString();
                                if (isLocalPath(pathStr)) {
                                  photoPaths.add(pathStr);
                                }
                              }
                            }
                            // Handle if item is a String
                            else if (item is String && item.isNotEmpty) {
                              if (isLocalPath(item)) {
                                photoPaths.add(item);
                              }
                            }
                          }
                        } else if (entry.value is Map) {
                          final map = entry.value as Map;
                          // Try to get local_path or localPath key
                          final localPath = map['local_path'] ?? map['localPath'] ?? map['path'];
                          if (localPath != null && localPath.toString().isNotEmpty) {
                            final pathStr = localPath.toString();
                            if (isLocalPath(pathStr)) {
                              photoPaths = [pathStr];
                            }
                          }
                        } else if (entry.value is String && entry.value.toString().isNotEmpty) {
                          final path = entry.value.toString();
                          
                          if (isLocalPath(path)) {
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
                      
                      // Form Data Section
                      if (data.formData.entries.any((entry) => !_isPhotoField(entry.key) && !_isOssField(entry.key))) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 20,
                              color: Theme.of(context).primaryColor,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Form Data',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
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
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    entry.value.toString(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                      
                      // Location Points Section
                      Row(
                        children: [
                          Icon(
                            Icons.my_location,
                            size: 20,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Location Points',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).primaryColor.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: Theme.of(context).primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${data.points.length} point${data.points.length > 1 ? "s" : ""} recorded',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isPhotoField(String fieldName) {
    // Cek berdasarkan field type di project
    final field = _currentProject.formFields.where((f) => f.label == fieldName).firstOrNull;
    if (field != null) {
      return field.type == FieldType.photo;
    }
    
    // Fallback: cek berdasarkan nama field
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

  IconData _getGeometryIcon() {
    switch (_currentProject.geometryType) {
      case GeometryType.point:
        return Icons.location_on;
      case GeometryType.line:
        return Icons.timeline;
      case GeometryType.polygon:
        return Icons.pentagon_outlined;
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
}
