import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project_model.dart';
import '../models/geo_data_model.dart';
import 'database_service.dart';
import 'storage_service.dart';
import 'photo_sync_service.dart';

class MigrationService {
  static final MigrationService _instance = MigrationService._internal();
  factory MigrationService() => _instance;
  MigrationService._internal();

  final DatabaseService _databaseService = DatabaseService();

  static const String _migrationKey = 'has_migrated_to_sqlite';
  static const String _projectsKey = 'projects';
  static const String _geoDataKey = 'geo_data';

  /// Flag one-time recovery untuk data yang terlanjur "synced" secara parsial
  /// (ada foto tanpa serverKey). Versi disematkan agar bisa dijalankan ulang
  /// bila logikanya perlu direvisi (mis. `_v2`).
  static const String _partialPhotoRecoveryKey =
      'has_recovered_partial_photo_sync_v1';

  /// Pulihkan record yang `isSynced=true` tetapi masih punya foto tanpa
  /// `serverKey` (bug sync parsial): reset menjadi unsynced supaya di-retry.
  ///
  /// Dijalankan sekali (di-guard [_partialPhotoRecoveryKey]) kecuali [force].
  /// Record dengan foto yang file lokalnya sudah hilang tetap di-reset (agar
  /// tampak "belum sync", bukan synced palsu) dan dihitung sebagai
  /// [PhotoSyncRecoveryResult.unrecoverable].
  Future<PhotoSyncRecoveryResult> recoverIncompletePhotoSyncs({
    StorageService? storage,
    PhotoSyncService? photoSync,
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force && (prefs.getBool(_partialPhotoRecoveryKey) ?? false)) {
      return PhotoSyncRecoveryResult(
        alreadyRun: true,
        scanned: 0,
        resetForRetry: 0,
        unrecoverable: 0,
      );
    }

    final store = storage ?? StorageService();
    final pss = photoSync ?? PhotoSyncService();

    int scanned = 0;
    int resetForRetry = 0;
    int unrecoverable = 0;

    try {
      final syncedRecords = await store.getSyncedGeoData();
      final projectCache = <String, Project?>{};

      for (final geoData in syncedRecords) {
        scanned++;

        final project = projectCache.putIfAbsent(
          geoData.projectId,
          () => null,
        );
        final resolvedProject =
            project ?? await store.getProjectById(geoData.projectId);
        projectCache[geoData.projectId] = resolvedProject;
        if (resolvedProject == null) continue; // tak bisa tentukan field foto

        final pending = pss.pendingPhotoUploads(geoData.formData, resolvedProject);
        if (pending.isEmpty) continue;

        await store.updateGeoDataSyncStatus(geoData.id, false);

        // Jika SEMUA foto pending filenya hilang → tak bisa dipulihkan.
        final allFilesGone = pending.every((p) => !p.fileExists);
        if (allFilesGone) {
          unrecoverable++;
        } else {
          resetForRetry++;
        }
      }
    } catch (e) {
      // Jangan set flag saat scan gagal — biarkan recovery dicoba lagi di
      // startup berikutnya, supaya error transien tidak melewatkan pemulihan.
      print('Error during partial photo sync recovery: $e');
      return PhotoSyncRecoveryResult(
        alreadyRun: false,
        scanned: scanned,
        resetForRetry: resetForRetry,
        unrecoverable: unrecoverable,
      );
    }

    await prefs.setBool(_partialPhotoRecoveryKey, true);

    return PhotoSyncRecoveryResult(
      alreadyRun: false,
      scanned: scanned,
      resetForRetry: resetForRetry,
      unrecoverable: unrecoverable,
    );
  }

  /// Check if migration has already been completed
  Future<bool> hasMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_migrationKey) ?? false;
  }

  /// Perform migration from SharedPreferences to SQLite
  Future<MigrationResult> migrate() async {
    try {
      // Check if already migrated
      if (await hasMigrated()) {
        return MigrationResult(
          success: true,
          message: 'Already migrated',
          projectsCount: 0,
          geoDataCount: 0,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      int projectsCount = 0;
      int geoDataCount = 0;

      // Migrate Projects
      final projectsJson = prefs.getStringList(_projectsKey) ?? [];
      for (var jsonStr in projectsJson) {
        try {
          final project = Project.fromJson(json.decode(jsonStr));
          await _databaseService.saveProject(project);
          projectsCount++;
        } catch (e) {
          print('Error migrating project: $e');
        }
      }

      // Migrate GeoData
      final allKeys = prefs.getKeys();
      for (var key in allKeys) {
        if (key.startsWith(_geoDataKey)) {
          final geoDataJsonList = prefs.getStringList(key) ?? [];
          for (var jsonStr in geoDataJsonList) {
            try {
              final geoData = GeoData.fromJson(json.decode(jsonStr));
              await _databaseService.saveGeoData(geoData);
              geoDataCount++;
            } catch (e) {
              print('Error migrating geo data: $e');
            }
          }
        }
      }

      // Mark migration as complete
      await prefs.setBool(_migrationKey, true);

      // Optional: Clear old SharedPreferences data after successful migration
      // Uncomment if you want to remove old data
      // await _clearOldData(prefs);

      return MigrationResult(
        success: true,
        message: 'Migration completed successfully',
        projectsCount: projectsCount,
        geoDataCount: geoDataCount,
      );
    } catch (e) {
      return MigrationResult(
        success: false,
        message: 'Migration failed: ${e.toString()}',
        projectsCount: 0,
        geoDataCount: 0,
      );
    }
  }

  /// Clear old SharedPreferences data (call after successful migration)
  Future<void> _clearOldData(SharedPreferences prefs) async {
    // Remove projects
    await prefs.remove(_projectsKey);

    // Remove all geo_data keys
    final allKeys = prefs.getKeys();
    for (var key in allKeys) {
      if (key.startsWith(_geoDataKey)) {
        await prefs.remove(key);
      }
    }
  }

  /// Force re-migration (for testing purposes)
  Future<void> resetMigration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_migrationKey);
  }

  /// Backup current SQLite data to SharedPreferences (for safety)
  Future<void> backupToSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Backup projects
    final projects = await _databaseService.loadProjects();
    final projectsJson = projects.map((p) => json.encode(p.toJson())).toList();
    await prefs.setStringList('backup_$_projectsKey', projectsJson);

    // Backup geo data by project
    for (var project in projects) {
      final geoDataList = await _databaseService.loadGeoData(project.id);
      final geoDataJson = geoDataList.map((g) => json.encode(g.toJson())).toList();
      await prefs.setStringList('backup_${_geoDataKey}_${project.id}', geoDataJson);
    }
  }
}

/// Hasil pemulihan record synced-parsial (foto tanpa serverKey).
class PhotoSyncRecoveryResult {
  /// True bila recovery dilewati karena sudah pernah dijalankan.
  final bool alreadyRun;

  /// Jumlah record synced yang diperiksa.
  final int scanned;

  /// Record yang di-reset & punya foto yang masih bisa di-upload (file ada).
  final int resetForRetry;

  /// Record yang di-reset tapi seluruh foto pending-nya hilang (tak pulih).
  final int unrecoverable;

  PhotoSyncRecoveryResult({
    required this.alreadyRun,
    required this.scanned,
    required this.resetForRetry,
    required this.unrecoverable,
  });

  int get totalReset => resetForRetry + unrecoverable;

  @override
  String toString() => alreadyRun
      ? 'PhotoSyncRecovery: already run'
      : 'PhotoSyncRecovery: scanned $scanned, reset $resetForRetry for retry, '
          '$unrecoverable unrecoverable';
}

class MigrationResult {
  final bool success;
  final String message;
  final int projectsCount;
  final int geoDataCount;

  MigrationResult({
    required this.success,
    required this.message,
    required this.projectsCount,
    required this.geoDataCount,
  });

  @override
  String toString() {
    if (success) {
      return 'Migration successful: $projectsCount projects, $geoDataCount geo data records';
    } else {
      return 'Migration failed: $message';
    }
  }
}
