import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:in_app_update/in_app_update.dart';
import 'screens/auth/splash_screen.dart';
import 'theme/app_theme.dart';
import 'services/firebase_messaging_service.dart';
import 'services/crashlytics_service.dart';
import 'services/location_service_v2.dart';
import "services/photo_migration_service.dart";
import 'services/update_service.dart';
import 'app_initializer.dart';
import 'services/settings_service.dart';

void main() async {
  // Wrap everything in a guarded zone — last-resort catcher for async errors
  // that slip past FlutterError.onError and PlatformDispatcher.onError.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 1. Initialize Firebase FIRST (CRITICAL!)
      try {
        await Firebase.initializeApp();
        debugPrint('✅ Firebase initialized successfully');

        // 2. Initialize Crashlytics (wires up all error handlers)
        await CrashlyticsService.instance.initialize();
        debugPrint('✅ Crashlytics initialized');

        // 3. Register FCM background handler
        FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler);
        debugPrint('✅ Background message handler registered');

        _runPhotoMigration();
      } catch (e, stack) {
        debugPrint('⚠️ Firebase initialization failed: $e');
        debugPrint('⚠️ App will continue without Firebase features');
        // Crashlytics may not be ready yet, so just log locally
        debugPrint(stack.toString());
      }

      // 4. Initialize app services (includes FCM if Firebase is ready)
      await AppInitializer().initialize();

      runApp(const TerestriaApp());
    },
    // Zone-level catcher: records as fatal so it groups like a crash
    (error, stack) {
      debugPrint('🔴 [Zone] Uncaught error: $error');
      crashlytics.recordFatalError(
        error,
        stack,
        reason: 'Uncaught zone error',
      );
    },
  );
}

Future<void> _runPhotoMigration() async {
  final migrationService = PhotoMigrationService();

  if (!await migrationService.isMigrationCompleted()) {
    print('🔄 Running photo migration...');
    final result =
        await migrationService.migratePhotosToPersistentStorage();
    if (result.hasErrors) {
      print('⚠️ Migration had errors: ${result.summary}');
    } else {
      print('✅ Migration completed: ${result.summary}');
    }
  }
}

class TerestriaApp extends StatefulWidget {
  const TerestriaApp({super.key});

  @override
  State<TerestriaApp> createState() => _TerestriaAppState();
}

class _TerestriaAppState extends State<TerestriaApp>
    with WidgetsBindingObserver {
  // Navigator key digunakan untuk mendapatkan context saat flexible update
  // selesai didownload, sehingga snackbar bisa ditampilkan dari mana saja.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('✅ App lifecycle observer added');

    // Cek apakah ada flexible update yang sudah didownload saat app resume
    // (misal user menutup app saat download berlangsung, lalu buka lagi)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFlexibleUpdateInstallStatus();
    });
  }

  /// Cek jika ada flexible update yang sudah selesai didownload
  /// dan belum diterapkan — tampilkan snackbar untuk ajak user restart.
  Future<void> _checkFlexibleUpdateInstallStatus() async {
    try {
      final info = await InAppUpdate.checkForUpdate()
          .timeout(const Duration(seconds: 8));

      if (info.installStatus == InstallStatus.downloaded) {
        debugPrint('🔄 [Main] Flexible update sudah didownload, tampilkan snackbar');
        final ctx = _navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          UpdateService().showInstallSnackbar(ctx);
        }
      }
    } catch (e) {
      // Offline atau Play Store tidak tersedia → skip
      debugPrint('⚠️ [Main] Install status check dilewati: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('🗑️ App lifecycle observer removed');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('📱 [MAIN APP] Lifecycle changed to: $state');

    if (state == AppLifecycleState.detached) {
      debugPrint('⚠️ [MAIN APP] App is being killed - ensuring cleanup...');
      _ensureBackgroundTrackingStopped();
    }
  }

  Future<void> _ensureBackgroundTrackingStopped() async {
    try {
      final locationService = LocationServiceV2();
      if (locationService.isActivelyTracking) {
        debugPrint('⚠️ [MAIN APP] Stopping active background tracking...');
        await locationService.stopBackgroundTracking();
        locationService.stopActiveTracking();
        debugPrint('✅ [MAIN APP] Background tracking stopped');
      } else {
        debugPrint('✅ [MAIN APP] No active tracking detected');
      }
    } catch (e, stack) {
      debugPrint('❌ [MAIN APP] Error stopping background tracking: $e');
      crashlytics.recordError(
        e,
        stack,
        reason: 'Error stopping background tracking on app detach',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsService().themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Terestria',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          navigatorKey: _navigatorKey,
          home: const SplashScreen(),
          // Navigator observer untuk breadcrumb screen transitions
          navigatorObservers: [CrashlyticsNavigatorObserver()],
        );
      },
    );
  }
}

/// Records screen navigation as Crashlytics breadcrumbs.
/// Helps trace which screen the user was on before a crash.
class CrashlyticsNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    final name = route.settings.name ?? route.runtimeType.toString();
    crashlytics.log('PUSH → $name');
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    final prev = previousRoute?.settings.name ??
        previousRoute?.runtimeType.toString() ??
        'unknown';
    crashlytics.log('POP → $prev');
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    final name = newRoute?.settings.name ??
        newRoute?.runtimeType.toString() ??
        'unknown';
    crashlytics.log('REPLACE → $name');
  }
}
