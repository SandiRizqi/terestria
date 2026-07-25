import 'package:flutter/material.dart';
import 'services/migration_service.dart';
import 'services/database_service.dart';
import 'services/firebase_messaging_service.dart';
import 'services/settings_service.dart';
import 'services/update_service.dart';

/// Initialize app services and perform migrations if needed
class AppInitializer {
  static final AppInitializer _instance = AppInitializer._internal();
  factory AppInitializer() => _instance;
  AppInitializer._internal();

  final MigrationService _migrationService = MigrationService();
  final DatabaseService _databaseService = DatabaseService();
  final SettingsService _settingsService = SettingsService();
  FirebaseMessagingService? _fcmService;

  bool _isInitialized = false;

  /// Initialize all app services
  /// [authToken] - Optional auth token for FCM registration
  Future<void> initialize({String? authToken}) async {
    if (_isInitialized) return;

    try {
      // 1. Initialize database
      await _databaseService.database;
      debugPrint('✅ Database initialized');

      // 2. Initialize Settings Service
      await _settingsService.initialize();
      debugPrint('✅ Settings initialized');

      // 3. Check and perform migration from SharedPreferences to SQLite
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

      // 3b. Pulihkan record yang terlanjur "synced" padahal fotonya belum
      // lengkap (bug sync parsial). Non-blocking: kegagalan tidak menghentikan
      // startup, dan flag hanya diset bila berhasil (akan dicoba lagi bila gagal).
      await _runPhotoSyncRecovery();

      // 4. Cek in-app update (fire-and-forget, aman saat offline)
      UpdateService().startUpdateCheck(null);
      debugPrint('✅ Update check initiated');

      // 5. Initialize Firebase Messaging (lazy initialization)
      try {
        _fcmService = FirebaseMessagingService();
        await _fcmService!.initialize(authToken: authToken);
        debugPrint('✅ Firebase Messaging initialized');
      } catch (e) {
        debugPrint('⚠️ Firebase Messaging initialization failed: $e');
        // Don't throw error, app can continue without FCM
      }

      _isInitialized = true;
      debugPrint('✅ App initialization completed');
    } catch (e) {
      debugPrint('❌ App initialization error: $e');
      rethrow;
    }
  }

  /// Jalankan pemulihan sync foto parsial dengan aman (tidak boleh
  /// menggagalkan startup). Recovery itu sendiri idempotent & di-guard flag.
  Future<void> _runPhotoSyncRecovery() async {
    try {
      final result = await _migrationService.recoverIncompletePhotoSyncs();
      if (!result.alreadyRun) {
        debugPrint('✅ Photo-sync recovery: $result');
      }
    } catch (e) {
      debugPrint('⚠️ Photo-sync recovery failed (non-fatal): $e');
    }
  }

  /// Update FCM auth token after login
  Future<void> updateFCMAuthToken(String authToken) async {
    try {
      if (_fcmService == null) {
        debugPrint('⚠️ FCM service not initialized, initializing now...');
        _fcmService = FirebaseMessagingService();
        await _fcmService!.initialize(authToken: authToken);
      }
      await _fcmService!.updateAuthToken(authToken);
      debugPrint('✅ FCM auth token updated');
    } catch (e) {
      debugPrint('⚠️ Failed to update FCM auth token: $e');
    }
  }

  /// Deactivate FCM token on logout
  Future<void> deactivateFCMToken(String authToken) async {
    try {
      if (_fcmService != null) {
        await _fcmService!.deactivateToken(authToken);
        debugPrint('✅ FCM token deactivated');
      } else {
        debugPrint('⚠️ FCM service not initialized, skipping deactivation');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to deactivate FCM token: $e');
    }
  }

  bool get isInitialized => _isInitialized;
}
