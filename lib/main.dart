import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/auth/splash_screen.dart';
import 'theme/app_theme.dart';
import 'services/firebase_messaging_service.dart';
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
  } catch (e) {
    debugPrint('⚠️ Firebase initialization failed: $e');
    debugPrint('⚠️ App will continue without FCM features');
  }
  
  // 3. Initialize app services (includes FCM if Firebase is ready)
  await AppInitializer().initialize();
  
  runApp(const TerestriaApp());
}

class TerestriaApp extends StatelessWidget {
  const TerestriaApp({super.key});

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
