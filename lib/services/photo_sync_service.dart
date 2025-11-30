import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';
import '../models/form_field_model.dart';
import '../models/project_model.dart';
import 'api_service.dart';

/// Photo metadata model
class PhotoMetadata {
  final String name;
  final String localPath;
  final String? serverUrl;
  final String? serverKey; // OSS key for stable reference
  final DateTime created;
  final DateTime updated;

  PhotoMetadata({
    required this.name,
    required this.localPath,
    this.serverUrl,
    this.serverKey,
    required this.created,
    required this.updated,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'localPath': localPath,
      'serverUrl': serverUrl,
      'serverKey': serverKey,
      'created': created.toIso8601String(),
      'updated': updated.toIso8601String(),
    };
  }

  factory PhotoMetadata.fromJson(Map<String, dynamic> json) {
    return PhotoMetadata(
      name: json['name'],
      localPath: json['localPath'],
      serverUrl: json['serverUrl'],
      serverKey: json['serverKey'],
      created: DateTime.parse(json['created']),
      updated: DateTime.parse(json['updated']),
    );
  }

  PhotoMetadata copyWith({
    String? name,
    String? localPath,
    String? serverUrl,
    String? serverKey,
    DateTime? created,
    DateTime? updated,
  }) {
    return PhotoMetadata(
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      serverUrl: serverUrl ?? this.serverUrl,
      serverKey: serverKey ?? this.serverKey,
      created: created ?? this.created,
      updated: updated ?? this.updated,
    );
  }
}

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
      
      final filename = ossUrl.split('/').last.split('?').first;
      final localPath = await _getPhotoPath(filename);
      final file = File(localPath);

      // print('FILE ; ${localPath}');

      // Check if already downloaded
      if (file.existsSync()) {
        print('Photo already exists locally: $localPath');
        return localPath;
      }

      // Download from OSS
      // print('Downloading photo from: $ossUrl');
      final response = await http.get(Uri.parse(ossUrl)).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Photo download timeout: $ossUrl');
        },
      );
      
      if (response.statusCode == 200) {
        // Ensure directory exists
        await file.parent.create(recursive: true);
        
        // Write file
        await file.writeAsBytes(response.bodyBytes);
        //print('Photo downloaded successfully: $localPath (${response.bodyBytes.length} bytes)');
        return localPath;
      } else {
        print('Download failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error downloading photo from $ossUrl: $e');
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
  /// NEW FORMAT: Returns array of PhotoMetadata objects
  Future<Map<String, dynamic>> processFormDataForPush(
    Map<String, dynamic> formData,
    Project project,
  ) async {
    final updatedFormData = Map<String, dynamic>.from(formData);

    for (var field in project.formFields) {
      if (field.type == FieldType.photo && formData.containsKey(field.label)) {
        final photoValue = formData[field.label];
        final List<PhotoMetadata> photoMetadataList = [];

        // Handle existing PhotoMetadata array format
        if (photoValue is List) {
          for (var item in photoValue) {
            PhotoMetadata? metadata;
            
            if (item is Map) {
              // Already in PhotoMetadata format
              try {
                metadata = PhotoMetadata.fromJson(Map<String, dynamic>.from(item));
              } catch (e) {
                print('Error parsing PhotoMetadata: $e');
                continue;
              }
            } else if (item is String && item.isNotEmpty) {
              // Old format: string path
              final file = File(item);
              final filename = file.path.split('/').last;
              metadata = PhotoMetadata(
                name: filename,
                localPath: item,
                serverUrl: null,
                created: DateTime.now(),
                updated: DateTime.now(),
              );
            }

            if (metadata != null) {
              // Upload if not yet uploaded (serverUrl is null)
              if (metadata.serverUrl == null && !metadata.localPath.startsWith('http')) {
                print('Uploading photo: ${metadata.name}');
                final ossData = await uploadSinglePhoto(metadata.localPath);
                
                if (ossData != null) {
                  metadata = metadata.copyWith(
                    serverUrl: ossData['file_url'],
                    serverKey: ossData['key'],
                    updated: DateTime.now(),
                  );
                  print('Photo uploaded: ${metadata.name} -> ${ossData['file_url']}');
                }
              }
              photoMetadataList.add(metadata);
            }
          }
        } else if (photoValue is String && photoValue.isNotEmpty) {
          // Single photo - old format
          final file = File(photoValue);
          final filename = file.path.split('/').last;
          var metadata = PhotoMetadata(
            name: filename,
            localPath: photoValue,
            serverUrl: null,
            created: DateTime.now(),
            updated: DateTime.now(),
          );

          // Upload if local path
          if (!photoValue.startsWith('http')) {
            print('Uploading single photo: ${metadata.name}');
            final ossData = await uploadSinglePhoto(photoValue);
            
            if (ossData != null) {
              metadata = metadata.copyWith(
                serverUrl: ossData['file_url'],
                serverKey: ossData['key'],
                updated: DateTime.now(),
              );
              print('Photo uploaded: ${metadata.name} -> ${ossData['file_url']}');
            }
          }
          photoMetadataList.add(metadata);
        }

        // Update form data with PhotoMetadata array
        if (photoMetadataList.isNotEmpty) {
          updatedFormData[field.label] = photoMetadataList.map((m) => m.toJson()).toList();
        }
      }
    }

    return updatedFormData;
  }

  /// Process form data for pull (download photos from OSS)
  /// NEW FORMAT: Handles array of PhotoMetadata objects
  Future<Map<String, dynamic>> processFormDataForPull(
    Map<String, dynamic> formData,
    Project? project,
  ) async {
    final updatedFormData = Map<String, dynamic>.from(formData);

    // Get photo fields from project
    final photoFields = project?.formFields
        .where((f) => f.type == FieldType.photo)
        .map((f) => f.label)
        .toSet() ?? <String>{};

    print('📥 Processing form data for pull. Photo fields: $photoFields');

    // Process each photo field
    for (var fieldName in photoFields) {
      if (!updatedFormData.containsKey(fieldName)) continue;

      final photoValue = updatedFormData[fieldName];
      final List<PhotoMetadata> photoMetadataList = [];

      if (photoValue is List) {
        for (var item in photoValue) {
          PhotoMetadata? metadata;

          if (item is Map) {
            // PhotoMetadata format
            try {
              metadata = PhotoMetadata.fromJson(Map<String, dynamic>.from(item));
              
              // Check if we need to download
              if (metadata.serverUrl != null) {
                final localFile = File(metadata.localPath);
                
                // Download only if file doesn't exist locally
                if (!localFile.existsSync()) {
                  // print('📥 Downloading new photo: ${metadata.name} (key: ${metadata.serverKey})');
                  final downloadedPath = await downloadPhoto(metadata.serverUrl!, fieldName);
                  
                  if (downloadedPath != null) {
                    metadata = metadata.copyWith(
                      localPath: downloadedPath,
                      updated: DateTime.now(),
                    );
                    // print('✅ Downloaded: ${metadata.name}');
                  } else {
                    print('❌ Failed to download: ${metadata.name}');
                  }
                } else {
                  print('⏭️ Skipping existing photo: ${metadata.name} (key: ${metadata.serverKey})');
                }
              }
            } catch (e) {
              print('Error parsing PhotoMetadata: $e');
              continue;
            }
          } else if (item is String && item.isNotEmpty) {
            // Old format: string path or URL
            if (item.startsWith('http')) {
              // It's a server URL - download it
              final filename = item.split('/').last;
              final localPath = await downloadPhoto(item, fieldName);
              
              if (localPath != null) {
                metadata = PhotoMetadata(
                  name: filename,
                  localPath: localPath,
                  serverUrl: item,
                  created: DateTime.now(),
                  updated: DateTime.now(),
                );
              }
            } else {
              // It's a local path
              final file = File(item);
              if (file.existsSync()) {
                final filename = file.path.split('/').last;
                metadata = PhotoMetadata(
                  name: filename,
                  localPath: item,
                  serverUrl: null,
                  created: DateTime.now(),
                  updated: DateTime.now(),
                );
              }
            }
          }

          if (metadata != null) {
            photoMetadataList.add(metadata);
          }
        }
      } else if (photoValue is String && photoValue.isNotEmpty) {
        // Single photo - old format
        PhotoMetadata? metadata;
        
        if (photoValue.startsWith('http')) {
          // Server URL
          final filename = photoValue.split('/').last;
          final localPath = await downloadPhoto(photoValue, fieldName);
          
          if (localPath != null) {
            metadata = PhotoMetadata(
              name: filename,
              localPath: localPath,
              serverUrl: photoValue,
              created: DateTime.now(),
              updated: DateTime.now(),
            );
          }
        } else {
          // Local path
          final file = File(photoValue);
          if (file.existsSync()) {
            final filename = file.path.split('/').last;
            metadata = PhotoMetadata(
              name: filename,
              localPath: photoValue,
              serverUrl: null,
              created: DateTime.now(),
              updated: DateTime.now(),
            );
          }
        }

        if (metadata != null) {
          photoMetadataList.add(metadata);
        }
      }

      // Update form data with PhotoMetadata array
      if (photoMetadataList.isNotEmpty) {
        updatedFormData[fieldName] = photoMetadataList.map((m) => m.toJson()).toList();
      } else {
        updatedFormData[fieldName] = [];
      }
    }

    return updatedFormData;
  }

  /// Get local path for photo storage (use cache directory like when uploading)
  Future<String> _getPhotoPath(String filename) async {
    // Use cache directory to match the path format from server
    // Server sends paths like: /data/user/0/com.example.geoform_app/cache/...
    final directory = await getTemporaryDirectory();
    final cacheDir = Directory(directory.path);
    
    if (!cacheDir.existsSync()) {
      await cacheDir.create(recursive: true);
    }
    
    return '${cacheDir.path}/$filename';
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

      //print('Cleaned up $deletedCount orphaned photos');
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
