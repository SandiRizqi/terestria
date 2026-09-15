import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:permission_handler/permission_handler.dart' show Permission;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import '../../utils/app_logger.dart';

class PermissionService {

  static const String _alwaysAskedKey = 'location_always_requested';

  /// Apakah perlu meminta izin "Always"? Hanya bila BELUM pernah ditanya DAN
  /// statusnya masih denied → cegah re-prompt tiap masuk layar (pure, teruji).
  static bool shouldRequestAlways({
    required bool alreadyAsked,
    required bool alwaysDenied,
  }) =>
      !alreadyAsked && alwaysDenied;

  /// Apakah background tracking akan bermasalah dengan izin saat ini?
  /// iOS HANYA mengirim lokasi di background bila izin "Always" (bukan
  /// When-In-Use). Bila iOS dan belum "Always" → true (harus diberi peringatan;
  /// track background bisa berhenti begitu app keluar dari foreground).
  /// Android memakai foreground-service, jadi When-In-Use pun cukup → false.
  static bool backgroundNeedsAlways({
    required bool isIOS,
    required LocationPermission permission,
  }) =>
      isIOS && permission != LocationPermission.always;

  /// Escalate ke "Always" untuk background tracking, lalu laporkan izin final.
  /// Dipanggil saat user MEMULAI tracking (aksi eksplisit), jadi meminta
  /// "Always" di sini wajar — iOS tak menampilkan dialog ulang bila sudah
  /// pernah diputuskan. Mengembalikan permission terkini setelah percobaan.
  static Future<LocationPermission> ensureBackgroundPermission() async {
    try {
      // Escalate hanya bila foreground sudah granted (syarat iOS/Android).
      final foreground = await Permission.locationWhenInUse.status;
      if (foreground.isGranted) {
        await Permission.locationAlways.request();
      }
    } catch (e) {
      logDebug('⚠️ ensureBackgroundPermission: gagal minta Always: $e');
    }
    return Geolocator.checkPermission();
  }

  /// Request ALL required permissions
  static Future<bool> requestAllPermissions() async {
    try {
      logDebug('🔐 ========================================');
      logDebug('🔐 Starting Permission Request Process');
      logDebug('🔐 ========================================');
      logDebug('📱 Platform: ${Platform.operatingSystem}');
      
      if (Platform.isIOS) {
        return await _requestIOSPermissions();
      } else {
        return await _requestAndroidPermissions();
      }
      
    } catch (e, stackTrace) {
      logError('❌ Permission error: $e');
      logDebug('Stack trace: $stackTrace');
      return false;
    }
  }
  
  /// iOS-specific permission flow
  static Future<bool> _requestIOSPermissions() async {
    logDebug('🍎 iOS Permission Flow Started');
    
    // 1. Check if location service is enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    logDebug('📍 Location service enabled: $serviceEnabled');
    
    if (!serviceEnabled) {
      logError('❌ Location service is disabled. Please enable in Settings.');
      return false;
    }
    
    // 2. Check current permission status
    var currentPermission = await Geolocator.checkPermission();
    logDebug('📍 Current Geolocator permission: $currentPermission');
    
    // 3. Request permission if denied
    if (currentPermission == LocationPermission.denied) {
      logDebug('📍 Permission is denied, requesting...');
      currentPermission = await Geolocator.requestPermission();
      logDebug('📍 Permission after request: $currentPermission');
      
      // Wait a bit for iOS to process
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Re-check
      currentPermission = await Geolocator.checkPermission();
      logDebug('📍 Permission re-checked: $currentPermission');
    }
    
    // 4. Handle different permission states
    if (currentPermission == LocationPermission.deniedForever) {
      logError('❌ Location permission is permanently denied');
      logDebug('💡 User must enable it manually in Settings');
      return false;
    }
    
    if (currentPermission == LocationPermission.denied) {
      logError('❌ Location permission is denied');
      return false;
    }
    
    // 5. Check if we got at least "When In Use" permission
    if (currentPermission == LocationPermission.whileInUse ||
        currentPermission == LocationPermission.always) {
      logDebug('✅ Location permission granted: $currentPermission');
      
      // 6. Minta "Always" HANYA SEKALI. Kalau user sudah memilih When-In-Use,
      //    jangan prompt "Always" lagi tiap masuk data collection (bug: dialog
      //    izin muncul terus di iOS). Foreground collection cukup When-In-Use.
      try {
        final prefs = await SharedPreferences.getInstance();
        final alreadyAsked = prefs.getBool(_alwaysAskedKey) ?? false;
        final alwaysStatus = await Permission.locationAlways.status;
        if (shouldRequestAlways(
            alreadyAsked: alreadyAsked, alwaysDenied: alwaysStatus.isDenied)) {
          logDebug('📍 Requesting "Always" (one-time)…');
          final alwaysResult = await Permission.locationAlways.request();
          await prefs.setBool(_alwaysAskedKey, true);
          logDebug('📍 "Always" request result: $alwaysResult');
        }
      } catch (e) {
        logDebug('⚠️ Could not request "Always" permission: $e');
      }
      
      // 7. Check precision (iOS 14+)
      try {
        final accuracy = await Geolocator.getLocationAccuracy();
        logDebug('🎯 Location accuracy: $accuracy');
        
        if (accuracy == LocationAccuracyStatus.reduced) {
          logDebug('⚠️ Reduced accuracy detected, requesting full accuracy...');
          final preciseGranted = await Geolocator.requestTemporaryFullAccuracy(
            purposeKey: 'PreciseLocationUsage',
          );
          logDebug('🎯 Full accuracy granted: $preciseGranted');
        } else {
          logDebug('✅ Full accuracy already enabled');
        }
      } catch (e) {
        logDebug('⚠️ Accuracy check not available (iOS < 14 or error): $e');
      }
      
      // 8. Request notification permission (for background tracking indicator)
      try {
        final notificationStatus = await Permission.notification.request();
        logDebug('🔔 Notification permission: $notificationStatus');
      } catch (e) {
        logDebug('⚠️ Notification permission error: $e');
      }
      
      logDebug('✅ iOS permissions successfully granted');
      return true;
    }
    
    logError('❌ Location permission not sufficient: $currentPermission');
    return false;
  }
  
  /// Android-specific permission flow
  static Future<bool> _requestAndroidPermissions() async {
    logDebug('🤖 Android Permission Flow Started');
    
    // Check if location service is enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    logDebug('📍 Location service enabled: $serviceEnabled');
    
    if (!serviceEnabled) {
      logError('❌ Location service is disabled');
      return false;
    }
    
    // 1. Request FOREGROUND location permission dulu.
    var locationStatus = await Permission.location.request();
    logDebug('📍 Location (foreground) permission: $locationStatus');

    if (locationStatus.isDenied || locationStatus.isPermanentlyDenied) {
      logError('❌ Foreground location permission denied');
      return false;
    }

    // 2. Request notification permission (Android 13+) untuk foreground service.
    var notificationStatus = await Permission.notification.request();
    logDebug('🔔 Notification permission: $notificationStatus');

    // 3. Background location (Android 10+) HANYA diminta SETELAH foreground
    //    granted. Android 11+ menolak request gabungan, jadi harus terpisah.
    //    Kegagalan di sini tidak memblokir foreground tracking.
    await requestBackgroundLocation();

    logDebug('✅ Android foreground permissions granted');
    return true;
  }

  /// Request izin background location secara terpisah.
  /// Aman dipanggil setelah foreground granted; mengembalikan true bila
  /// background diizinkan (untuk tracking saat app di background).
  static Future<bool> requestBackgroundLocation() async {
    try {
      final current = await Permission.locationWhenInUse.status;
      if (!current.isGranted) {
        logDebug('⚠️ Foreground belum granted, lewati request background');
        return false;
      }

      final alwaysStatus = await Permission.locationAlways.request();
      logDebug('📍 Background location permission: $alwaysStatus');
      return alwaysStatus.isGranted;
    } catch (e) {
      logDebug('⚠️ requestBackgroundLocation error: $e');
      return false;
    }
  }
  
  /// Check if location service is enabled
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }
  
  /// Open app settings (mis. saat permission deniedForever).
  static Future<bool> openAppSettings() async {
    // FIX: panggil fungsi dari package permission_handler (via prefix `ph`),
    // bukan memanggil method ini sendiri (dulu rekursi tak terhingga).
    return await ph.openAppSettings();
  }
  
  /// Get detailed permission status for debugging
  static Future<Map<String, dynamic>> getDetailedStatus() async {
    try {
      final Map<String, dynamic> status = {
        'platform': Platform.operatingSystem,
        'serviceEnabled': await Geolocator.isLocationServiceEnabled(),
        'geolocator_permission': (await Geolocator.checkPermission()).toString(),
      };
      
      // Permission Handler status
      try {
        status['permission_location'] = (await Permission.location.status).toString();
        status['permission_locationAlways'] = (await Permission.locationAlways.status).toString();
        status['permission_notification'] = (await Permission.notification.status).toString();
      } catch (e) {
        status['permission_handler_error'] = e.toString();
      }
      
      // iOS specific
      if (Platform.isIOS) {
        try {
          final accuracy = await Geolocator.getLocationAccuracy();
          status['accuracy'] = accuracy.toString();
        } catch (e) {
          status['accuracy'] = 'unavailable (iOS < 14)';
        }
      }
      
      return status;
    } catch (e) {
      return {'error': e.toString()};
    }
  }
  
  /// Check if we have sufficient permissions
  static Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
           permission == LocationPermission.always;
  }
}