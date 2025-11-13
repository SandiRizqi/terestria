import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';
import '../models/form_field_model.dart';
import '../models/project_model.dart';
import 'api_service.dart';

class PhotoSyncService {
  static final PhotoSyncService _instance = PhotoSyncService._internal();
  factory PhotoSyncService() => _instance;
  PhotoSyncService._internal();

  final ApiService _apiService = ApiService();

  /// Upload single photo to OSS
  Future<Map<String, String>?> uploadSinglePhoto(String localPath) async {
    try {
      final file = File(localPath);
      if (!file.existsSync()) {
        print('Photo file not found: $localPath');
        return null;
      }

      // Upload file
      final response = await _apiService.uploadFile(
        '${ApiConfig.baseUrl}/uploadfile/',
        file,
      );

      if (response != null && response['success'] == true) {
        return {
          'file_url': response['file_url'],
          'key': response['key'],
        };
      }

      print('Upload failed: $response');
      return null;
    } catch (e) {
      print('Error uploading photo: $e');
      return null;
    }
  }

  /// Upload multiple photos in parallel
  Future<List<Map<String, String>>> uploadMultiplePhotos(List<String> localPaths) async {
    final results = <Map<String, String>>[];
    
    // Upload in parallel with limit
    final futures = localPaths.map((path) => uploadSinglePhoto(path));
    final responses = await Future.wait(futures);
    
    for (var response in responses) {
      if (response != null) {
        results.add(response);
      }
    }
    
    return results;
  }

  /// Download single photo from OSS
  Future<String?> downloadPhoto(String ossUrl, String fieldName) async {
    try {
      // Generate local filename from OSS URL
      final filename = ossUrl.split('/').last;
      final localPath = await _getPhotoPath(filename);
      final file = File(localPath);

      // Check if already downloaded
      if (file.existsSync()) {
        print('Photo already exists locally: $localPath');
        return localPath;
      }

      // Download from OSS
      print('Downloading photo from: $ossUrl');
      final response = await http.get(Uri.parse(ossUrl));
      
      if (response.statusCode == 200) {
        // Ensure directory exists
        await file.parent.create(recursive: true);
        
        // Write file
        await file.writeAsBytes(response.bodyBytes);
        print('Photo downloaded successfully: $localPath');
        return localPath;
      } else {
        print('Download failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error downloading photo: $e');
      return null;
    }
  }

  /// Download multiple photos in parallel
  Future<List<String>> downloadMultiplePhotos(List<String> ossUrls, String fieldName) async {
    final results = <String>[];
    
    // Download in parallel
    final futures = ossUrls.map((url) => downloadPhoto(url, fieldName));
    final responses = await Future.wait(futures);
    
    for (var response in responses) {
      if (response != null) {
        results.add(response);
      }
    }
    
    return results;
  }

  /// Process form data for push (upload photos and get OSS URLs)
  Future<Map<String, dynamic>> processFormDataForPush(
    Map<String, dynamic> formData,
    Project project,
  ) async {
    final updatedFormData = Map<String, dynamic>.from(formData);

    for (var field in project.formFields) {
      if (field.type == FieldType.photo && formData.containsKey(field.label)) {
        final photoValue = formData[field.label];

        // Skip if already has OSS URL
        if (formData.containsKey('${field.label}_oss_url') || 
            formData.containsKey('${field.label}_oss_urls')) {
          continue;
        }

        if (photoValue is String && photoValue.isNotEmpty && !photoValue.startsWith('http')) {
          // Single photo - upload if not already uploaded
          print('Uploading single photo for ${field.label}: $photoValue');
          final ossData = await uploadSinglePhoto(photoValue);
          
          if (ossData != null) {
            updatedFormData['${field.label}_oss_url'] = ossData['file_url'];
            updatedFormData['${field.label}_oss_key'] = ossData['key'];
            print('Photo uploaded: ${ossData['file_url']}');
          }
        } else if (photoValue is List && photoValue.isNotEmpty) {
          // Multiple photos - filter out http URLs (already uploaded)
          final localPaths = photoValue
              .where((p) => p is String && p.isNotEmpty && !p.startsWith('http'))
              .map((p) => p.toString())
              .toList();

          if (localPaths.isNotEmpty) {
            print('Uploading ${localPaths.length} photos for ${field.label}');
            final ossDataList = await uploadMultiplePhotos(localPaths);
            
            if (ossDataList.isNotEmpty) {
              updatedFormData['${field.label}_oss_urls'] = 
                  ossDataList.map((o) => o['file_url']).toList();
              updatedFormData['${field.label}_oss_keys'] = 
                  ossDataList.map((o) => o['key']).toList();
              print('${ossDataList.length} photos uploaded');
            }
          }
        }
      }
    }

    return updatedFormData;
  }

  /// Process form data for pull (download photos from OSS)
  Future<Map<String, dynamic>> processFormDataForPull(
    Map<String, dynamic> formData,
    Project? project,
  ) async {
    final updatedFormData = Map<String, dynamic>.from(formData);

    // Process each entry in form data
    for (var entry in formData.entries) {
      // Single photo
      if (entry.key.endsWith('_oss_url') && entry.value is String) {
        final fieldName = entry.key.replaceAll('_oss_url', '');
        final ossUrl = entry.value as String;

        // Download and save locally
        print('Downloading photo for $fieldName from: $ossUrl');
        final localPath = await downloadPhoto(ossUrl, fieldName);
        
        if (localPath != null) {
          updatedFormData[fieldName] = localPath;
          print('Photo saved locally: $localPath');
        }
      }

      // Multiple photos
      if (entry.key.endsWith('_oss_urls') && entry.value is List) {
        final fieldName = entry.key.replaceAll('_oss_urls', '');
        final ossUrls = (entry.value as List)
            .where((url) => url is String && url.isNotEmpty)
            .map((url) => url.toString())
            .toList();

        if (ossUrls.isNotEmpty) {
          print('Downloading ${ossUrls.length} photos for $fieldName');
          final localPaths = await downloadMultiplePhotos(ossUrls, fieldName);
          
          if (localPaths.isNotEmpty) {
            updatedFormData[fieldName] = localPaths;
            print('${localPaths.length} photos saved locally');
          }
        }
      }
    }

    return updatedFormData;
  }

  /// Get local path for photo storage
  Future<String> _getPhotoPath(String filename) async {
    final directory = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${directory.path}/photos');
    
    if (!photosDir.existsSync()) {
      await photosDir.create(recursive: true);
    }
    
    return '${photosDir.path}/$filename';
  }

  /// Clean up orphaned photos (photos not referenced in any geodata)
  Future<void> cleanupOrphanedPhotos(List<String> referencedPaths) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');
      
      if (!photosDir.existsSync()) return;

      final files = photosDir.listSync();
      int deletedCount = 0;

      for (var file in files) {
        if (file is File) {
          final isReferenced = referencedPaths.any((path) => path == file.path);
          
          if (!isReferenced) {
            await file.delete();
            deletedCount++;
          }
        }
      }

      print('Cleaned up $deletedCount orphaned photos');
    } catch (e) {
      print('Error cleaning up photos: $e');
    }
  }

  /// Get total size of photos directory
  Future<int> getPhotoStorageSize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');
      
      if (!photosDir.existsSync()) return 0;

      int totalSize = 0;
      final files = photosDir.listSync(recursive: true);

      for (var file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      return totalSize;
    } catch (e) {
      print('Error calculating photo storage size: $e');
      return 0;
    }
  }

  /// Format bytes to human readable
  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
