import 'services/migration_service.dart';
import 'services/database_service.dart';
import 'services/firebase_messaging_service.dart';
import 'services/settings_service.dart';
import 'services/update_service.dart';

import 'utils/app_logger.dart';
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
      logDebug('✅ Database initialized', tag: 'APP');

      // 2. Initialize Settings Service
      await _settingsService.initialize();
      logDebug('✅ Settings initialized', tag: 'APP');

      // 3. Check and perform migration from SharedPreferences to SQLite
      final hasMigrated = await _migrationService.hasMigrated();
      
      if (!hasMigrated) {
        logDebug('🔄 Starting migration from SharedPreferences to SQLite...', tag: 'APP');
        final migrationResult = await _migrationService.migrate();
        
        if (migrationResult.success) {
          logDebug('✅ Migration completed: ${migrationResult.projectsCount} projects, ${migrationResult.geoDataCount} geo data', tag: 'APP');
        } else {
          logError('❌ Migration failed: ${migrationResult.message}', tag: 'APP');
        }
      } else {
        logDebug('✅ Already migrated to SQLite', tag: 'APP');
      }

      // 3b. Pulihkan record yang terlanjur "synced" padahal fotonya belum
      // lengkap (bug sync parsial). Non-blocking: kegagalan tidak menghentikan
      // startup, dan flag hanya diset bila berhasil (akan dicoba lagi bila gagal).
      await _runPhotoSyncRecovery();

      // 4. Cek in-app update (fire-and-forget, aman saat offline)
      UpdateService().startUpdateCheck(null);
      logDebug('✅ Update check initiated', tag: 'APP');

      // 5. Initialize Firebase Messaging (lazy initialization)
      try {
        _fcmService = FirebaseMessagingService();
        await _fcmService!.initialize(authToken: authToken);
        logDebug('✅ Firebase Messaging initialized', tag: 'APP');
      } catch (e) {
        logWarn('⚠️ Firebase Messaging initialization failed: $e', tag: 'APP');
        // Don't throw error, app can continue without FCM
      }

      _isInitialized = true;
      logDebug('✅ App initialization completed', tag: 'APP');
    } catch (e) {
      logError('❌ App initialization error: $e', tag: 'APP');
      rethrow;
    }
  }

  /// Jalankan pemulihan sync foto parsial dengan aman (tidak boleh
  /// menggagalkan startup). Recovery itu sendiri idempotent & di-guard flag.
  Future<void> _runPhotoSyncRecovery() async {
    try {
      final result = await _migrationService.recoverIncompletePhotoSyncs();
      if (!result.alreadyRun) {
        logDebug('✅ Photo-sync recovery: $result', tag: 'APP');
      }
    } catch (e) {
      logWarn('⚠️ Photo-sync recovery failed (non-fatal): $e', tag: 'APP');
    }
  }

  /// Update FCM auth token after login
  Future<void> updateFCMAuthToken(String authToken) async {
    try {
      if (_fcmService == null) {
        logWarn('⚠️ FCM service not initialized, initializing now...', tag: 'APP');
        _fcmService = FirebaseMessagingService();
        await _fcmService!.initialize(authToken: authToken);
      }
      await _fcmService!.updateAuthToken(authToken);
      logDebug('✅ FCM auth token updated', tag: 'APP');
    } catch (e) {
      logWarn('⚠️ Failed to update FCM auth token: $e', tag: 'APP');
    }
  }

  /// Deactivate FCM token on logout
  Future<void> deactivateFCMToken(String authToken) async {
    try {
      if (_fcmService != null) {
        await _fcmService!.deactivateToken(authToken);
        logDebug('✅ FCM token deactivated', tag: 'APP');
      } else {
        logWarn('⚠️ FCM service not initialized, skipping deactivation', tag: 'APP');
      }
    } catch (e) {
      logWarn('⚠️ Failed to deactivate FCM token: $e', tag: 'APP');
    }
  }

  bool get isInitialized => _isInitialized;
}
