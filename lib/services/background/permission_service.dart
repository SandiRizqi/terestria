import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io' show Platform;

class PermissionService {
  
  /// Request ALL required permissions
  static Future<bool> requestAllPermissions() async {
    try {
      print('🔐 ========================================');
      print('🔐 Starting Permission Request Process');
      print('🔐 ========================================');
      print('📱 Platform: ${Platform.operatingSystem}');
      
      if (Platform.isIOS) {
        return await _requestIOSPermissions();
      } else {
        return await _requestAndroidPermissions();
      }
      
    } catch (e, stackTrace) {
      print('❌ Permission error: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }
  
  /// iOS-specific permission flow
  static Future<bool> _requestIOSPermissions() async {
    print('🍎 iOS Permission Flow Started');
    
    // 1. Check if location service is enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    print('📍 Location service enabled: $serviceEnabled');
    
    if (!serviceEnabled) {
      print('❌ Location service is disabled. Please enable in Settings.');
      return false;
    }
    
    // 2. Check current permission status
    var currentPermission = await Geolocator.checkPermission();
    print('📍 Current Geolocator permission: $currentPermission');
    
    // 3. Request permission if denied
    if (currentPermission == LocationPermission.denied) {
      print('📍 Permission is denied, requesting...');
      currentPermission = await Geolocator.requestPermission();
      print('📍 Permission after request: $currentPermission');
      
      // Wait a bit for iOS to process
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Re-check
      currentPermission = await Geolocator.checkPermission();
      print('📍 Permission re-checked: $currentPermission');
    }
    
    // 4. Handle different permission states
    if (currentPermission == LocationPermission.deniedForever) {
      print('❌ Location permission is permanently denied');
      print('💡 User must enable it manually in Settings');
      return false;
    }
    
    if (currentPermission == LocationPermission.denied) {
      print('❌ Location permission is denied');
      return false;
    }
    
    // 5. Check if we got at least "When In Use" permission
    if (currentPermission == LocationPermission.whileInUse ||
        currentPermission == LocationPermission.always) {
      print('✅ Location permission granted: $currentPermission');
      
      // 6. Try to request "Always" permission (optional, may not show immediately)
      try {
        print('📍 Attempting to request "Always" permission...');
        
        // Use permission_handler for "Always" request
        final alwaysStatus = await Permission.locationAlways.status;
        print('📍 Current "Always" status: $alwaysStatus');
        
        if (alwaysStatus.isDenied) {
          final alwaysResult = await Permission.locationAlways.request();
          print('📍 "Always" request result: $alwaysResult');
        }
      } catch (e) {
        print('⚠️ Could not request "Always" permission: $e');
        print('💡 This is OK - iOS may show it later automatically');
      }
      
      // 7. Check precision (iOS 14+)
      try {
        final accuracy = await Geolocator.getLocationAccuracy();
        print('🎯 Location accuracy: $accuracy');
        
        if (accuracy == LocationAccuracyStatus.reduced) {
          print('⚠️ Reduced accuracy detected, requesting full accuracy...');
          final preciseGranted = await Geolocator.requestTemporaryFullAccuracy(
            purposeKey: 'PreciseLocationUsage',
          );
          print('🎯 Full accuracy granted: $preciseGranted');
        } else {
          print('✅ Full accuracy already enabled');
        }
      } catch (e) {
        print('⚠️ Accuracy check not available (iOS < 14 or error): $e');
      }
      
      // 8. Request notification permission (for background tracking indicator)
      try {
        final notificationStatus = await Permission.notification.request();
        print('🔔 Notification permission: $notificationStatus');
      } catch (e) {
        print('⚠️ Notification permission error: $e');
      }
      
      print('✅ iOS permissions successfully granted');
      return true;
    }
    
    print('❌ Location permission not sufficient: $currentPermission');
    return false;
  }
  
  /// Android-specific permission flow
  static Future<bool> _requestAndroidPermissions() async {
    print('🤖 Android Permission Flow Started');
    
    // Check if location service is enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    print('📍 Location service enabled: $serviceEnabled');
    
    if (!serviceEnabled) {
      print('❌ Location service is disabled');
      return false;
    }
    
    // Request basic location permission
    var locationStatus = await Permission.location.request();
    print('📍 Location permission: $locationStatus');
    
    if (locationStatus.isDenied || locationStatus.isPermanentlyDenied) {
      print('❌ Location permission denied');
      return false;
    }
    
    // Request background location (Android 10+)
    var locationAlwaysStatus = await Permission.locationAlways.request();
    print('📍 Background location permission: $locationAlwaysStatus');
    
    // Request notification permission (Android 13+)
    var notificationStatus = await Permission.notification.request();
    print('🔔 Notification permission: $notificationStatus');
    
    print('✅ Android permissions granted');
    return true;
  }
  
  /// Check if location service is enabled
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }
  
  /// Open app settings
  static Future<void> openAppSettings() async {
    await openAppSettings();
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