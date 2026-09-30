import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';
import '../models/form_field_model.dart';
import '../models/project_model.dart';
import 'api_service.dart';

import '../utils/app_logger.dart';
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

/// Foto yang belum ter-upload ke OSS (belum punya `serverKey`).
/// Dipakai untuk memutuskan apakah sebuah geodata boleh ditandai synced
/// dan untuk memulihkan data yang terlanjur "synced" secara parsial.
class PendingPhoto {
  final String fieldLabel;
  final String name;
  final String localPath;

  /// True bila file lokal masih ada → masih bisa di-upload ulang.
  /// False → foto tidak bisa dipulihkan (file hilang).
  final bool fileExists;

  PendingPhoto({
    required this.fieldLabel,
    required this.name,
    required this.localPath,
    required this.fileExists,
  });

  @override
  String toString() =>
      'PendingPhoto($fieldLabel/$name, fileExists: $fileExists)';
}

class PhotoSyncService {
  static final PhotoSyncService _instance = PhotoSyncService._internal();
  factory PhotoSyncService() => _instance;

  final ApiService _apiService;

  PhotoSyncService._internal() : _apiService = ApiService();

  /// Konstruktor untuk pengujian: memungkinkan injeksi [ApiService].
  PhotoSyncService.forTest({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  /// Batas jumlah upload foto yang berjalan bersamaan dalam satu record.
  /// Dua cukup untuk mempercepat record berfoto banyak; lebih dari itu
  /// membagi bandwidth sinyal lapangan yang sempit sehingga setiap upload
  /// lebih lambat dan lebih mudah timeout.
  static const int maxConcurrentUploads = 2;

  /// Kembalikan daftar foto pada [formData] yang belum ter-upload ke OSS,
  /// yaitu item foto dengan `serverKey == null` dan `localPath` bukan URL http.
  ///
  /// Hanya field bertipe [FieldType.photo] pada [project] yang diperiksa.
  /// Hasil kosong berarti semua foto sudah punya `serverKey` → aman ditandai
  /// synced.
  List<PendingPhoto> pendingPhotoUploads(
    Map<String, dynamic> formData,
    Project project,
  ) {
    final pending = <PendingPhoto>[];

    for (final field in project.formFields) {
      if (field.type != FieldType.photo) continue;
      if (!formData.containsKey(field.label)) continue;

      final value = formData[field.label];

      void addIfLocal(String localPath, String name) {
        if (localPath.isEmpty || localPath.startsWith('http')) return;
        pending.add(PendingPhoto(
          fieldLabel: field.label,
          name: name,
          localPath: localPath,
          fileExists: File(localPath).existsSync(),
        ));
      }

      if (value is List) {
        for (final item in value) {
          if (item is Map) {
            if (item['serverKey'] != null) continue; // sudah ter-upload
            final localPath = (item['localPath'] ?? '').toString();
            final name = (item['name'] ?? localPath.split('/').last).toString();
            addIfLocal(localPath, name);
          } else if (item is String) {
            addIfLocal(item, item.split('/').last);
          }
        }
      } else if (value is String) {
        addIfLocal(value, value.split('/').last);
      }
    }

    return pending;
  }

  /// Salin `serverKey`/`serverUrl` hasil upload dari [latest] (versi DB
  /// terbaru) ke foto yang sama (`localPath`) di [edited] yang belum punya
  /// key. Layar edit menyimpan dari snapshot saat dibuka; tanpa ini upload
  /// foto oleh auto-sync selama user mengedit hilang → foto diunggah ulang.
  /// Nilai lain (termasuk foto yang dihapus user) tetap mengikuti [edited].
  static Map<String, dynamic> mergeUploadedPhotoKeys(
    Map<String, dynamic> edited,
    Map<String, dynamic> latest,
    Project project,
  ) {
    final out = Map<String, dynamic>.of(edited);
    for (final field in project.formFields) {
      if (field.type != FieldType.photo) continue;
      final mine = out[field.label];
      final theirs = latest[field.label];
      if (mine is! List || theirs is! List) continue;

      final uploaded = <String, Map>{
        for (final t in theirs)
          if (t is Map && t['serverKey'] != null && t['localPath'] != null)
            t['localPath'].toString(): t,
      };
      out[field.label] = [
        for (final item in mine)
          if (item is Map &&
              item['serverKey'] == null &&
              uploaded.containsKey(item['localPath']?.toString()))
            {
              ...item,
              'serverKey': uploaded[item['localPath'].toString()]!['serverKey'],
              'serverUrl': uploaded[item['localPath'].toString()]!['serverUrl'],
            }
          else
            item,
      ];
    }
    return out;
  }

  /// Apakah foto ini masih perlu di-upload ke OSS?
  ///
  /// Predikat tunggal untuk seluruh alur push, di-*key* ke `serverKey` (bukan
  /// `serverUrl`). `serverKey` adalah identitas stabil di OSS; `serverUrl`
  /// hanyalah signed URL yang diregenerasi server saat fetch, jadi tidak boleh
  /// dipakai sebagai penanda "sudah ter-upload". Ini juga menyamakan keputusan
  /// push dengan [pendingPhotoUploads] agar tidak terjadi deadlock (guard
  /// menganggap pending sementara push menolak re-upload).
  bool needsUpload(PhotoMetadata m) =>
      m.serverKey == null && !m.localPath.startsWith('http');

  /// Upload single photo to OSS
  Future<Map<String, String>?> uploadSinglePhoto(String localPath) async {
    try {
      final file = File(localPath);
      if (!file.existsSync()) {
        logDebug('Photo file not found: $localPath', tag: 'SYNC');
        return null;
      }

      // Upload file — batas waktu mengikuti ukuran file (foto besar di
      // sinyal lemah tak lagi pasti gagal di 120 dtk).
      final size = await file.length();
      final response = await _apiService.uploadFile(
        '${ApiConfig.baseUrl}/uploadfile/',
        file,
        timeout: ApiConfig.uploadTimeoutFor(size),
      );

      if (response != null && response['success'] == true) {
        return {
          'file_url': response['file_url'],
          'key': response['key'],
        };
      }

      logWarn('Photo upload rejected for ${localPath.split('/').last}: '
          '$response', tag: 'SYNC');
      return null;
    } catch (e, st) {
      logWarn('Error uploading photo ${localPath.split('/').last}',
          tag: 'SYNC', error: e, stack: st);
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
        logDebug('Photo already exists locally: $localPath', tag: 'SYNC');
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
        logWarn('Download failed with status: ${response.statusCode}', tag: 'SYNC');
        return null;
      }
    } catch (e) {
      // Strip query string — it carries the OSS signature/credentials.
      logWarn('Error downloading photo from ${ossUrl.split('?').first}: $e', tag: 'SYNC');
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

  /// Upload satu foto bila perlu; kembalikan metadata dengan `serverKey`/
  /// `serverUrl` terisi bila sukses. Bila gagal, metadata dikembalikan apa
  /// adanya (serverKey tetap null → tertangkap guard sync).
  Future<PhotoMetadata> _uploadIfNeeded(PhotoMetadata metadata) async {
    if (!needsUpload(metadata)) return metadata;

    logDebug('Uploading photo: ${metadata.name}', tag: 'SYNC');
    final ossData = await uploadSinglePhoto(metadata.localPath);
    if (ossData != null) {
      final updated = metadata.copyWith(
        serverUrl: ossData['file_url'],
        serverKey: ossData['key'],
        updated: DateTime.now(),
      );
      logDebug('Photo uploaded: ${updated.name} -> key=${ossData['key']}', tag: 'SYNC');
      return updated;
    }
    return metadata;
  }

  /// Upload foto yang belum ter-upload di [metas] dengan konkurensi terbatas
  /// ([maxConcurrentUploads]). Urutan & posisi item dipertahankan (hasil
  /// ditulis balik ke indeks asalnya).
  Future<void> _uploadPendingConcurrently(List<PhotoMetadata> metas) async {
    final pendingIndexes = [
      for (var i = 0; i < metas.length; i++)
        if (needsUpload(metas[i])) i,
    ];

    for (var start = 0;
        start < pendingIndexes.length;
        start += maxConcurrentUploads) {
      final batch =
          pendingIndexes.skip(start).take(maxConcurrentUploads).toList();
      final results =
          await Future.wait(batch.map((i) => _uploadIfNeeded(metas[i])));
      for (var j = 0; j < batch.length; j++) {
        metas[batch[j]] = results[j];
      }
    }
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
          // Parse dulu (jaga urutan), baru upload yang perlu secara paralel.
          for (var item in photoValue) {
            if (item is Map) {
              // Already in PhotoMetadata format
              try {
                photoMetadataList
                    .add(PhotoMetadata.fromJson(Map<String, dynamic>.from(item)));
              } catch (e) {
                logWarn('Error parsing PhotoMetadata: $e', tag: 'SYNC');
                continue;
              }
            } else if (item is String && item.isNotEmpty) {
              // Old format: string path
              photoMetadataList.add(PhotoMetadata(
                name: item.split('/').last,
                localPath: item,
                serverUrl: null,
                created: DateTime.now(),
                updated: DateTime.now(),
              ));
            }
          }

          await _uploadPendingConcurrently(photoMetadataList);
        } else if (photoValue is String && photoValue.isNotEmpty) {
          // Single photo - old format
          final metadata = await _uploadIfNeeded(PhotoMetadata(
            name: photoValue.split('/').last,
            localPath: photoValue,
            serverUrl: null,
            created: DateTime.now(),
            updated: DateTime.now(),
          ));
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

    logDebug('📥 Processing form data for pull. Photo fields: $photoFields', tag: 'SYNC');

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
                    logError('❌ Failed to download: ${metadata.name}', tag: 'SYNC');
                  }
                } else {
                  logDebug('⏭️ Skipping existing photo: ${metadata.name} (key: ${metadata.serverKey})', tag: 'SYNC');
                }
              }
            } catch (e) {
              logWarn('Error parsing PhotoMetadata: $e', tag: 'SYNC');
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

  /// Get persistent photo directory for originals (WILL NOT BE DELETED on update/cache clear)
  Future<Directory> _getPersistentPhotoDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${appDir.path}/photos/originals');
    
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    
    return photoDir;
  }

  /// Get downloaded photo directory (persistent)
  Future<Directory> _getDownloadedPhotoDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${appDir.path}/photos/downloaded');
    
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    
    return photoDir;
  }

  /// Get local path for photo storage (use persistent directory instead of cache)
  Future<String> _getPhotoPath(String filename) async {
    // ✅ CHANGED: Use persistent storage instead of cache
    // This ensures photos survive app updates and cache clearing
    final photoDir = await _getDownloadedPhotoDirectory();
    return '${photoDir.path}/$filename';
  }

  /// Clean up orphaned photos (photos not referenced in any geodata)
  Future<void> cleanupOrphanedPhotos(List<String> referencedPaths) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');
      
      if (!await photosDir.exists()) return;

      // Clean both originals and downloaded folders
      final originalsDir = Directory('${photosDir.path}/originals');
      final downloadedDir = Directory('${photosDir.path}/downloaded');
      
      int deletedCount = 0;
      
      // Clean originals folder
      if (await originalsDir.exists()) {
        final files = originalsDir.listSync();
        for (var file in files) {
          if (file is File) {
            final isReferenced = referencedPaths.any((path) => path == file.path);
            
            if (!isReferenced) {
              await file.delete();
              deletedCount++;
            }
          }
        }
      }
      
      // Clean downloaded folder
      if (await downloadedDir.exists()) {
        final files = downloadedDir.listSync();
        for (var file in files) {
          if (file is File) {
            final isReferenced = referencedPaths.any((path) => path == file.path);
            
            if (!isReferenced) {
              await file.delete();
              deletedCount++;
            }
          }
        }
      }

      logDebug('Cleaned up $deletedCount orphaned photos from persistent storage', tag: 'SYNC');
    } catch (e) {
      logWarn('Error cleaning up photos: $e', tag: 'SYNC');
    }
  }

  /// Get total size of photos directory (persistent storage)
  Future<int> getPhotoStorageSize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');
      
      if (!await photosDir.exists()) return 0;

      int totalSize = 0;
      final files = photosDir.listSync(recursive: true);

      for (var file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      return totalSize;
    } catch (e) {
      logWarn('Error calculating photo storage size: $e', tag: 'SYNC');
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
