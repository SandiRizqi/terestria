import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/auth/splash_screen.dart';
import 'theme/app_theme.dart';
import 'services/firebase_messaging_service.dart';
import 'services/location_service_v2.dart';
import "services/photo_migration_service.dart";
import 'app_initializer.dart';

void main() async {
  // Initialize Flutter binding
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase FIRST (CRITICAL!)
  try {
    await Firebase.initializeApp();
    debugPrint('✅ Firebase initialized successfully');
    
    // 2. Register background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    debugPrint('✅ Background message handler registered');

    _runPhotoMigration();
  } catch (e) {
    debugPrint('⚠️ Firebase initialization failed: $e');
    debugPrint('⚠️ App will continue without FCM features');
  }
  
  // 3. Initialize app services (includes FCM if Firebase is ready)
  await AppInitializer().initialize();
  
  runApp(const TerestriaApp());
}


Future<void> _runPhotoMigration() async {
  final migrationService = PhotoMigrationService();
  
  // Check if migration needed
  if (!await migrationService.isMigrationCompleted()) {
    print('🔄 Running photo migration...');
    
    // Run migration - NOTE: Correct method name
    final result = await migrationService.migratePhotosToPersistentStorage();
    
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

class _TerestriaAppState extends State<TerestriaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('✅ App lifecycle observer added');
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

    // ✅ ONLY stop on detached (app killed), NOT on paused (minimized)
    if (state == AppLifecycleState.detached) {
      debugPrint('⚠️ [MAIN APP] App is being killed - ensuring cleanup...');
      // Force stop any background tracking when app is closed
      _ensureBackgroundTrackingStopped();
    }
  }

  Future<void> _ensureBackgroundTrackingStopped() async {
    try {
      // Import LocationServiceV2
      final locationService = LocationServiceV2();
      
      // Only stop if actively tracking
      if (locationService.isActivelyTracking) {
        debugPrint('⚠️ [MAIN APP] Stopping active background tracking...');
        await locationService.stopBackgroundTracking();
        locationService.stopActiveTracking();
        debugPrint('✅ [MAIN APP] Background tracking stopped');
      } else {
        debugPrint('✅ [MAIN APP] No active tracking detected');
      }
    } catch (e) {
      debugPrint('❌ [MAIN APP] Error stopping background tracking: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terestria',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}
