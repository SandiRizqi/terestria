import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/project_model.dart';
import '../models/form_field_model.dart';
import '../services/storage_service.dart';
import '../services/photo_sync_service.dart';

/// Service untuk migrate foto dari cache directory ke persistent storage
/// Dijalankan sekali saat app update
class PhotoMigrationService {
  static final PhotoMigrationService _instance = PhotoMigrationService._internal();
  factory PhotoMigrationService() => _instance;
  PhotoMigrationService._internal();

  final StorageService _storageService = StorageService();
  
  /// Check if migration has been completed
  Future<bool> isMigrationCompleted() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final migrationFlag = File('${appDir.path}/.photo_migration_completed');
      return await migrationFlag.exists();
    } catch (e) {
      print('Error checking migration status: $e');
      return false;
    }
  }
  
  /// Mark migration as completed
  Future<void> markMigrationCompleted() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final migrationFlag = File('${appDir.path}/.photo_migration_completed');
      await migrationFlag.writeAsString(DateTime.now().toIso8601String());
      print('✅ Photo migration marked as completed');
    } catch (e) {
      print('Error marking migration completed: $e');
    }
  }
  
  /// Migrate existing photos from cache to persistent storage
  Future<MigrationResult> migratePhotosToPersistentStorage() async {
    print('🔄 Starting photo migration from cache to persistent storage...');
    
    int totalPhotos = 0;
    int migratedPhotos = 0;
    int failedPhotos = 0;
    int skippedPhotos = 0;
    final List<String> errors = [];
    
    try {
      // Check if migration already completed
      if (await isMigrationCompleted()) {
        print('⏭️ Photo migration already completed, skipping...');
        return MigrationResult(
          totalPhotos: 0,
          migratedPhotos: 0,
          failedPhotos: 0,
          skippedPhotos: 0,
          errors: [],
          alreadyCompleted: true,
        );
      }
      
      final allProjects = await _storageService.loadProjects();
      
      for (var project in allProjects) {
        final geoDataList = await _storageService.loadGeoData(project.id);
        
        for (var geoData in geoDataList) {
          bool hasChanges = false;
          final updatedFormData = Map<String, dynamic>.from(geoData.formData);
          
          for (var field in project.formFields) {
            if (field.type == FieldType.photo && 
                geoData.formData.containsKey(field.label)) {
              
              final photoValue = geoData.formData[field.label];
              
              if (photoValue is List) {
                final updatedPhotos = <Map<String, dynamic>>[];
                
                for (var photoJson in photoValue) {
                  totalPhotos++;
                  
                  if (photoJson is Map) {
                    try {
                      // Convert dynamic map to Map<String, dynamic>
                      final jsonMap = Map<String, dynamic>.from(
                        photoJson.map((key, value) => MapEntry(key.toString(), value))
                      );
                      final photoData = PhotoMetadata.fromJson(jsonMap);
                      
                      // Check if photo is in cache directory
                      if (photoData.localPath.contains('/cache/')) {
                        final file = File(photoData.localPath);
                        
                        if (file.existsSync()) {
                          // Copy to persistent storage
                          final newPath = await _copyToPersistent(
                            photoData.localPath, 
                            photoData.name
                          );
                          
                          if (newPath != null) {
                            final updatedPhoto = PhotoMetadata(
                              name: photoData.name,
                              localPath: newPath,
                              serverUrl: photoData.serverUrl,
                              serverKey: photoData.serverKey,
                              created: photoData.created,
                              updated: DateTime.now(),
                            );
                            
                            updatedPhotos.add(updatedPhoto.toJson());
                            hasChanges = true;
                            migratedPhotos++;
                            print('✅ Migrated: ${photoData.name}');
                          } else {
                            failedPhotos++;
                            errors.add('Failed to copy ${photoData.name}');
                            // Keep original if migration fails
                            updatedPhotos.add(
                            Map<String, dynamic>.from(
                              photoJson.map((k, v) => MapEntry(k.toString(), v))
                            )
                          );
                          }
                        } else {
                          // File doesn't exist in cache anymore
                          print('⚠️ Photo not found: ${photoData.localPath}');
                          skippedPhotos++;
                          
                          // If there's a server URL, we can re-download it later
                          if (photoData.serverUrl != null) {
                            updatedPhotos.add(
                            Map<String, dynamic>.from(
                              photoJson.map((k, v) => MapEntry(k.toString(), v))
                            )
                          );
                          }
                        }
                      } else {
                        // Already in persistent storage or external path
                        updatedPhotos.add(
                            Map<String, dynamic>.from(
                              photoJson.map((k, v) => MapEntry(k.toString(), v))
                            )
                          );

                        skippedPhotos++;
                      }
                    } catch (e) {
                      print('❌ Error parsing photo: $e');
                      failedPhotos++;
                      errors.add('Error parsing photo: $e');
                      updatedPhotos.add(
                            Map<String, dynamic>.from(
                              photoJson.map((k, v) => MapEntry(k.toString(), v))
                            )
                          );
                    }
                  }
                }
                
                if (hasChanges) {
                  updatedFormData[field.label] = updatedPhotos;
                }
              }
            }
          }
          
          if (hasChanges) {
            final updatedGeoData = geoData.copyWith(
              formData: updatedFormData,
              updatedAt: DateTime.now(),
            );
            
            await _storageService.saveGeoData(updatedGeoData);
            print('💾 Updated geodata: ${geoData.id}');
          }
        }
      }
      
      // Mark migration as completed
      await markMigrationCompleted();
      
      print('✅ Photo migration completed!');
      print('   Total photos: $totalPhotos');
      print('   Migrated: $migratedPhotos');
      print('   Failed: $failedPhotos');
      print('   Skipped: $skippedPhotos');
      
      return MigrationResult(
        totalPhotos: totalPhotos,
        migratedPhotos: migratedPhotos,
        failedPhotos: failedPhotos,
        skippedPhotos: skippedPhotos,
        errors: errors,
        alreadyCompleted: false,
      );
    } catch (e) {
      print('❌ Photo migration error: $e');
      errors.add('Migration error: $e');
      
      return MigrationResult(
        totalPhotos: totalPhotos,
        migratedPhotos: migratedPhotos,
        failedPhotos: failedPhotos,
        skippedPhotos: skippedPhotos,
        errors: errors,
        alreadyCompleted: false,
      );
    }
  }
  
  /// Copy photo to persistent storage
  Future<String?> _copyToPersistent(String sourcePath, String filename) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${appDir.path}/photos/originals');
      
      if (!await photoDir.exists()) {
        await photoDir.create(recursive: true);
      }
      
      final destPath = '${photoDir.path}/$filename';
      final sourceFile = File(sourcePath);
      
      if (await sourceFile.exists()) {
        await sourceFile.copy(destPath);
        return destPath;
      } else {
        print('⚠️ Source file not found: $sourcePath');
        return null;
      }
    } catch (e) {
      print('❌ Error copying photo: $e');
      return null;
    }
  }
  
  /// Get migration statistics
  Future<Map<String, dynamic>> getMigrationStats() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final appDir = await getApplicationDocumentsDirectory();
      
      // Count photos in cache
      int cachePhotoCount = 0;
      final cacheFiles = Directory(cacheDir.path).listSync(recursive: true);
      for (var file in cacheFiles) {
        if (file is File && _isImageFile(file.path)) {
          cachePhotoCount++;
        }
      }
      
      // Count photos in persistent storage
      int persistentPhotoCount = 0;
      final photoDir = Directory('${appDir.path}/photos');
      if (await photoDir.exists()) {
        final persistentFiles = photoDir.listSync(recursive: true);
        for (var file in persistentFiles) {
          if (file is File && _isImageFile(file.path)) {
            persistentPhotoCount++;
          }
        }
      }
      
      return {
        'cachePhotoCount': cachePhotoCount,
        'persistentPhotoCount': persistentPhotoCount,
        'migrationCompleted': await isMigrationCompleted(),
      };
    } catch (e) {
      print('Error getting migration stats: $e');
      return {
        'cachePhotoCount': 0,
        'persistentPhotoCount': 0,
        'migrationCompleted': false,
        'error': e.toString(),
      };
    }
  }
  
  bool _isImageFile(String path) {
    final extension = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
  }
}

/// Result of photo migration
class MigrationResult {
  final int totalPhotos;
  final int migratedPhotos;
  final int failedPhotos;
  final int skippedPhotos;
  final List<String> errors;
  final bool alreadyCompleted;
  
  MigrationResult({
    required this.totalPhotos,
    required this.migratedPhotos,
    required this.failedPhotos,
    required this.skippedPhotos,
    required this.errors,
    required this.alreadyCompleted,
  });
  
  bool get hasErrors => errors.isNotEmpty || failedPhotos > 0;
  bool get isSuccess => !hasErrors && (alreadyCompleted || migratedPhotos == totalPhotos);
  
  String get summary {
    if (alreadyCompleted) {
      return 'Migration already completed';
    }
    
    if (totalPhotos == 0) {
      return 'No photos to migrate';
    }
    
    return 'Migrated $migratedPhotos of $totalPhotos photos'
           '${failedPhotos > 0 ? ' ($failedPhotos failed)' : ''}'
           '${skippedPhotos > 0 ? ' ($skippedPhotos skipped)' : ''}';
  }
}
