import 'package:flutter/material.dart';
import 'services/migration_service.dart';
import 'services/database_service.dart';

/// Initialize app services and perform migrations if needed
class AppInitializer {
  static final AppInitializer _instance = AppInitializer._internal();
  factory AppInitializer() => _instance;
  AppInitializer._internal();

  final MigrationService _migrationService = MigrationService();
  final DatabaseService _databaseService = DatabaseService();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Initialize database
      await _databaseService.database;
      debugPrint('✅ Database initialized');

      // 2. Check and perform migration from SharedPreferences to SQLite
      final hasMigrated = await _migrationService.hasMigrated();
      
      if (!hasMigrated) {
        debugPrint('🔄 Starting migration from SharedPreferences to SQLite...');
        final migrationResult = await _migrationService.migrate();
        
        if (migrationResult.success) {
          debugPrint('✅ Migration completed: ${migrationResult.projectsCount} projects, ${migrationResult.geoDataCount} geo data');
        } else {
          debugPrint('❌ Migration failed: ${migrationResult.message}');
        }
      } else {
        debugPrint('✅ Already migrated to SQLite');
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('❌ App initialization error: $e');
      rethrow;
    }
  }

  bool get isInitialized => _isInitialized;
}
