import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project_model.dart';
import '../models/geo_data_model.dart';
import 'database_service.dart';

class MigrationService {
  static final MigrationService _instance = MigrationService._internal();
  factory MigrationService() => _instance;
  MigrationService._internal();

  final DatabaseService _databaseService = DatabaseService();
  
  static const String _migrationKey = 'has_migrated_to_sqlite';
  static const String _projectsKey = 'projects';
  static const String _geoDataKey = 'geo_data';

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
