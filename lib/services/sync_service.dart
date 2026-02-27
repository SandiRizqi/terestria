import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'api_service.dart';
import '../config/api_config.dart';
import '../models/geo_data_model.dart';
import '../models/project_model.dart';
import '../models/form_field_model.dart';
import 'storage_service.dart';
import 'photo_sync_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final PhotoSyncService _photoSyncService = PhotoSyncService();

  // ==================== UPLOAD TO SERVER ====================

  /// Sync single GeoData to backend
  Future<SyncResult> syncGeoData(GeoData geoData, Project project) async {
    try {
      // Step 1: Upload photos to OSS and get URLs
      print('Processing photos for geodata ${geoData.id}...');
      final processedFormData = await _photoSyncService.processFormDataForPush(
        geoData.formData,
        project,
      );

      // Step 2: Prepare data untuk dikirim (dengan OSS URLs)
      final Map<String, dynamic> payload = {
        'id': geoData.id,
        'project_id': geoData.projectId,
        'project_name': project.name,
        'geometry_type': project.geometryType.toString().split('.').last,
        'form_data': processedFormData,
        'points': geoData.points.map((point) => {
          'latitude': point.latitude,
          'longitude': point.longitude,
          'altitude': point.altitude,
          'accuracy': point.accuracy,
          'timestamp': point.timestamp.toIso8601String(),
        }).toList(),
        'created_at': geoData.createdAt.toIso8601String(),
        'updated_at': geoData.updatedAt.toIso8601String(),
        'synced_at': DateTime.now().toIso8601String(),
        //'project_id': geoData.projectId,
      };

      // Gunakan ApiService yang sudah include token
      final response = await _apiService.post(
        ApiConfig.syncDataEndpoint,
        body: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        
        // Update local geodata with OSS URLs
        final updatedGeoData = geoData.copyWith(
          formData: processedFormData,
          isSynced: true,
          syncedAt: DateTime.now(),
        );
        await _storageService.saveGeoData(updatedGeoData);
        
        return SyncResult(
          success: true,
          message: responseData['message'] ?? 'Data synced successfully',
          data: responseData,
        );
      } else {
        return SyncResult(
          success: false,
          message: 'Server error: ${response.statusCode} - ${response.body}',
        );
      }
    } on SocketException {
      return SyncResult(
        success: false,
        message: 'No internet connection',
      );
    } on TimeoutException {
      return SyncResult(
        success: false,
        message: 'Connection timeout',
      );
    } on ApiException catch (e) {
      return SyncResult(
        success: false,
        message: e.message,
      );
    } on FormatException catch (e) {
      return SyncResult(
        success: false,
        message: 'Invalid response format: ${e.message}',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Sync failed: ${e.toString()}',
      );
    }
  }

  /// Sync Project to backend
  Future<SyncResult> syncProject(Project project) async {
    try {
      // Prepare project data untuk dikirim
      final Map<String, dynamic> payload = {
        'id': project.id,
        'name': project.name,
        'description': project.description,
        'geometry_type': project.geometryType.toString().split('.').last,
        'form_fields': project.formFields.map((field) => {
          'id': field.id,
          'label': field.label,
          'type': field.type.toString().split('.').last,
          'required': field.required,
          'options': field.options,
          if (field.minPhotos != null) 'minPhotos': field.minPhotos,
          if (field.maxPhotos != null) 'maxPhotos': field.maxPhotos,
        }).toList(),
        'created_at': project.createdAt.toIso8601String(),
        'updated_at': project.updatedAt.toIso8601String(),
        'synced_at': DateTime.now().toIso8601String(),
      };

      // Gunakan ApiService yang sudah include token
      final response = await _apiService.post(
        ApiConfig.syncProjectEndpoint,
        body: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        
        // Update sync status in local database
        await _storageService.updateProjectSyncStatus(
          project.id,
          true,
          syncedAt: DateTime.now(),
        );
        
        return SyncResult(
          success: true,
          message: responseData['message'] ?? 'Project synced successfully',
          data: responseData,
        );
      } else {
        return SyncResult(
          success: false,
          message: 'Server error: ${response.statusCode} - ${response.body}',
        );
      }
    } on SocketException {
      return SyncResult(
        success: false,
        message: 'No internet connection',
      );
    } on TimeoutException {
      return SyncResult(
        success: false,
        message: 'Connection timeout',
      );
    } on ApiException catch (e) {
      return SyncResult(
        success: false,
        message: e.message,
      );
    } on FormatException catch (e) {
      return SyncResult(
        success: false,
        message: 'Invalid response format: ${e.message}',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Sync failed: ${e.toString()}',
      );
    }
  }

  /// Sync multiple GeoData
  Future<BatchSyncResult> syncMultipleGeoData(
    List<GeoData> geoDataList,
    Project project,
  ) async {
    int successCount = 0;
    int failCount = 0;
    List<String> errors = [];

    for (var geoData in geoDataList) {
      final result = await syncGeoData(geoData, project);
      if (result.success) {
        successCount++;
      } else {
        failCount++;
        errors.add('${geoData.id}: ${result.message}');
      }
    }

    return BatchSyncResult(
      total: geoDataList.length,
      successCount: successCount,
      failCount: failCount,
      errors: errors,
    );
  }

  /// Sync all unsynced data to server (Upload)
  Future<FullSyncResult> syncAllUnsyncedData() async {
    int projectsSuccess = 0;
    int projectsFail = 0;
    int geoDataSuccess = 0;
    int geoDataFail = 0;
    List<String> errors = [];

    try {
      // 1. Sync unsynced projects first
      final unsyncedProjects = await _storageService.getUnsyncedProjects();
      
      for (var project in unsyncedProjects) {
        final result = await syncProject(project);
        if (result.success) {
          projectsSuccess++;
        } else {
          projectsFail++;
          errors.add('Project ${project.name}: ${result.message}');
        }
      }

      // 2. Sync unsynced geo data
      final unsyncedGeoData = await _storageService.getUnsyncedGeoData();
      
      for (var geoData in unsyncedGeoData) {
        // Get project info
        final project = await _storageService.getProjectById(geoData.projectId);
        if (project != null) {
          final result = await syncGeoData(geoData, project);
          if (result.success) {
            geoDataSuccess++;
          } else {
            geoDataFail++;
            errors.add('GeoData ${geoData.id}: ${result.message}');
          }
        } else {
          geoDataFail++;
          errors.add('GeoData ${geoData.id}: Project not found');
        }
      }

      return FullSyncResult(
        projectsTotal: unsyncedProjects.length,
        projectsSuccess: projectsSuccess,
        projectsFail: projectsFail,
        geoDataTotal: unsyncedGeoData.length,
        geoDataSuccess: geoDataSuccess,
        geoDataFail: geoDataFail,
        errors: errors,
      );
    } catch (e) {
      return FullSyncResult(
        projectsTotal: 0,
        projectsSuccess: projectsSuccess,
        projectsFail: projectsFail,
        geoDataTotal: 0,
        geoDataSuccess: geoDataSuccess,
        geoDataFail: geoDataFail,
        errors: [...errors, 'Full sync error: ${e.toString()}'],
      );
    }
  }

  // ==================== DOWNLOAD FROM SERVER ====================

  /// Pull projects from server and save to local database
  Future<SyncResult> pullProjectsFromServer() async {
    try {
      final response = await _apiService.get(ApiConfig.syncProjectEndpoint);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final projectsList = responseData['data'] as List? ?? [];

        int savedCount = 0;
        for (var projectJson in projectsList) {
          print(projectJson);
          try {
            // Parse project from server format
            final project = _parseProjectFromServer(projectJson);

        
            
            // Check if project exists locally
            final existingProject = await _storageService.getProjectById(project.id);
            
            if (existingProject == null) {
              // New project from server - save it
              await _storageService.saveProject(project);
              savedCount++;
            } else {
              // Project exists - check if server version is newer
              final serverUpdatedAt = project.updatedAt;
              final localUpdatedAt = existingProject.updatedAt;
              
              if (serverUpdatedAt.isAfter(localUpdatedAt)) {
                // Server version is newer - update local
                await _storageService.saveProject(project);
                savedCount++;
              }
            }
          } catch (e) {
            print('Error parsing project: $e');
          }
        }

        return SyncResult(
          success: true,
          message: 'Downloaded $savedCount projects from server',
          data: {'count': savedCount},
        );
      } else {
        return SyncResult(
          success: false,
          message: 'Server error: ${response.statusCode}',
        );
      }
    } on SocketException {
      return SyncResult(
        success: false,
        message: 'No internet connection',
      );
    } on TimeoutException {
      return SyncResult(
        success: false,
        message: 'Connection timeout',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Pull projects failed: ${e.toString()}',
      );
    }
  }

  /// Pull geo data for a specific project from server
  Future<SyncResult> pullGeoDataFromServer(String projectId) async {
    try {
      final response = await _apiService.get(
        '${ApiConfig.syncDataEndpoint}?project_id=$projectId',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final geoDataList = responseData['data'] as List? ?? [];

        // Get project for photo field identification
        final project = await _storageService.getProjectById(projectId);

        int savedCount = 0;
        int updatedCount = 0;
        for (var geoDataJson in geoDataList) {
          try {
            // Parse geo data from server format
            final geoData = _parseGeoDataFromServer(geoDataJson);
            
            // Check if geo data exists locally
            final existingGeoData = await _storageService.getGeoDataById(geoData.id);
            
            if (existingGeoData == null) {
              // New geo data from server - download photos and save
              print('New geodata from server: ${geoData.id}');
              final processedFormData = await _photoSyncService.processFormDataForPull(
                geoData.formData,
                project,
              );
              
              final updatedGeoData = geoData.copyWith(formData: processedFormData);
              await _storageService.saveGeoData(updatedGeoData);
              savedCount++;
            } else {
              // Geo data exists - check if server version is newer
              final serverUpdatedAt = geoData.updatedAt;
              final localUpdatedAt = existingGeoData.updatedAt;
              
              if (serverUpdatedAt.isAfter(localUpdatedAt)) {
                // Server version is newer - download photos and update local
                print('Updating geodata from server: ${geoData.id}');
                final processedFormData = await _photoSyncService.processFormDataForPull(
                  geoData.formData,
                  project,
                );
                
                final updatedGeoData = geoData.copyWith(formData: processedFormData);
                await _storageService.saveGeoData(updatedGeoData);
                updatedCount++;
              }
            }
          } catch (e) {
            print('Error parsing geo data: $e');
          }
        }

        return SyncResult(
          success: true,
          message: 'Downloaded $savedCount geo data records from server',
          data: {'count': savedCount},
        );
      } else {
        return SyncResult(
          success: false,
          message: 'Server error: ${response.statusCode}',
        );
      }
    } on SocketException {
      return SyncResult(
        success: false,
        message: 'No internet connection',
      );
    } on TimeoutException {
      return SyncResult(
        success: false,
        message: 'Connection timeout',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Pull geo data failed: ${e.toString()}',
      );
    }
  }

  /// Two-way sync: Upload local changes and download server changes
  Future<TwoWaySyncResult> performTwoWaySync() async {
    try {
      // Step 1: Upload local unsynced data to server
      final uploadResult = await syncAllUnsyncedData();

      // Step 2: Download projects from server
      final projectsDownloadResult = await pullProjectsFromServer();

      // Step 3: Download geo data for all projects
      final projects = await _storageService.loadProjects();
      int totalGeoDataDownloaded = 0;
      
      for (var project in projects) {
        final geoDataDownloadResult = await pullGeoDataFromServer(project.id);
        if (geoDataDownloadResult.success && geoDataDownloadResult.data != null) {
          totalGeoDataDownloaded += geoDataDownloadResult.data!['count'] as int? ?? 0;
        }
      }

      return TwoWaySyncResult(
        success: true,
        uploadResult: uploadResult,
        projectsDownloaded: projectsDownloadResult.data?['count'] as int? ?? 0,
        geoDataDownloaded: totalGeoDataDownloaded,
        message: 'Two-way sync completed successfully',
      );
    } catch (e) {
      return TwoWaySyncResult(
        success: false,
        uploadResult: FullSyncResult(
          projectsTotal: 0,
          projectsSuccess: 0,
          projectsFail: 0,
          geoDataTotal: 0,
          geoDataSuccess: 0,
          geoDataFail: 0,
          errors: [],
        ),
        projectsDownloaded: 0,
        geoDataDownloaded: 0,
        message: 'Two-way sync failed: ${e.toString()}',
      );
    }
  }

  // ==================== HELPER METHODS ====================

  Project _parseProjectFromServer(Map<String, dynamic> json) {
    // Parse form fields
    final formFieldsList = json['form_fields'] as List? ?? [];
    final formFields = formFieldsList.map((fieldJson) {
      return FormFieldModel(
        id: fieldJson['id'],
        label: fieldJson['label'],
        type: _parseFieldType(fieldJson['type']),
        required: fieldJson['required'] ?? false,
        options: fieldJson['options'] != null 
            ? List<String>.from(fieldJson['options'])
            : null,
        minPhotos: fieldJson['minPhotos'] as int?,
        maxPhotos: fieldJson['maxPhotos'] as int?,
      );
    }).toList();

    return Project(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      geometryType: _parseGeometryType(json['geometry_type']),
      formFields: formFields,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      isSynced: true,
      syncedAt: json['synced_at'] != null 
          ? DateTime.parse(json['synced_at'])
          : DateTime.now(),
      createdBy: json['created_by'],
    );
  }

  GeoData _parseGeoDataFromServer(Map<String, dynamic> json) {
    // Parse points
    final pointsList = json['points'] as List? ?? [];
    final points = pointsList.map((pointJson) {
      return GeoPoint(
        latitude: pointJson['latitude'],
        longitude: pointJson['longitude'],
        altitude: pointJson['altitude'],
        accuracy: pointJson['accuracy'],
        timestamp: pointJson['timestamp'] != null
            ? DateTime.parse(pointJson['timestamp'])
            : DateTime.now(),
      );
    }).toList();

    return GeoData(
      id: json['id'],
      projectId: json['project_id'],
      formData: Map<String, dynamic>.from(json['form_data'] ?? {}),
      points: points,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      isSynced: true,
      collectedBy: json['collected_by'],
      syncedAt: json['synced_at'] != null 
          ? DateTime.parse(json['synced_at'])
          : DateTime.now(),
    );
  }

  GeometryType _parseGeometryType(String type) {
    switch (type.toLowerCase()) {
      case 'point':
        return GeometryType.point;
      case 'line':
        return GeometryType.line;
      case 'polygon':
        return GeometryType.polygon;
      default:
        return GeometryType.point;
    }
  }

  FieldType _parseFieldType(String type) {
    switch (type.toLowerCase()) {
      case 'text':
        return FieldType.text;
      case 'number':
        return FieldType.number;
      case 'date':
        return FieldType.date;
      case 'dropdown':
        return FieldType.dropdown;
      case 'checkbox':
        return FieldType.checkbox;
      case 'photo':
        return FieldType.photo;
      default:
        return FieldType.text;
    }
  }

  /// Process form data for pull (wrapper for PhotoSyncService)
  Future<Map<String, dynamic>> processFormDataForPull(
    Map<String, dynamic> formData,
    Project? project,
  ) async {
    return await _photoSyncService.processFormDataForPull(formData, project);
  }

  /// Process form data for push (wrapper for PhotoSyncService)
  Future<Map<String, dynamic>> processFormDataForPush(
    Map<String, dynamic> formData,
    Project project,
  ) async {
    return await _photoSyncService.processFormDataForPush(formData, project);
  }

  /// Test connection to backend
  Future<bool> testConnection() async {
    try {
      // Test dengan endpoint root atau health check
      final response = await _apiService.get('/')
          .timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200 || 
             response.statusCode == 404 || 
             response.statusCode == 401; // Server responds
    } catch (_) {
      return false;
    }
  }
}

// ==================== RESULT CLASSES ====================

class SyncResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  SyncResult({
    required this.success,
    required this.message,
    this.data,
  });
}

class BatchSyncResult {
  final int total;
  final int successCount;
  final int failCount;
  final List<String> errors;

  BatchSyncResult({
    required this.total,
    required this.successCount,
    required this.failCount,
    required this.errors,
  });

  bool get hasErrors => failCount > 0;
  bool get allSuccess => successCount == total;
  
  String get summary {
    if (allSuccess) {
      return 'All $total records synced successfully';
    } else if (successCount > 0) {
      return '$successCount of $total records synced. $failCount failed.';
    } else {
      return 'Failed to sync all records';
    }
  }
}

class FullSyncResult {
  final int projectsTotal;
  final int projectsSuccess;
  final int projectsFail;
  final int geoDataTotal;
  final int geoDataSuccess;
  final int geoDataFail;
  final List<String> errors;

  FullSyncResult({
    required this.projectsTotal,
    required this.projectsSuccess,
    required this.projectsFail,
    required this.geoDataTotal,
    required this.geoDataSuccess,
    required this.geoDataFail,
    required this.errors,
  });

  bool get hasErrors => projectsFail > 0 || geoDataFail > 0 || errors.isNotEmpty;
  bool get allSuccess => projectsSuccess == projectsTotal && geoDataSuccess == geoDataTotal;

  String get summary {
    final List<String> parts = [];
    
    if (projectsTotal > 0) {
      parts.add('Projects: $projectsSuccess/$projectsTotal synced');
    }
    
    if (geoDataTotal > 0) {
      parts.add('Data: $geoDataSuccess/$geoDataTotal synced');
    }
    
    if (parts.isEmpty) {
      return 'No data to sync';
    }
    
    return parts.join(', ');
  }
}

class TwoWaySyncResult {
  final bool success;
  final FullSyncResult uploadResult;
  final int projectsDownloaded;
  final int geoDataDownloaded;
  final String message;

  TwoWaySyncResult({
    required this.success,
    required this.uploadResult,
    required this.projectsDownloaded,
    required this.geoDataDownloaded,
    required this.message,
  });

  String get summary {
    final List<String> parts = [];
    
    // Upload summary
    if (uploadResult.projectsTotal > 0 || uploadResult.geoDataTotal > 0) {
      parts.add('Uploaded: ${uploadResult.summary}');
    }
    
    // Download summary
    if (projectsDownloaded > 0 || geoDataDownloaded > 0) {
      parts.add('Downloaded: $projectsDownloaded projects, $geoDataDownloaded data');
    }
    
    if (parts.isEmpty) {
      return 'Already in sync';
    }
    
    return parts.join(' | ');
  }
}
