import 'dart:async';
import 'dart:io';
import 'package:location/location.dart' as loc;
import '../../models/geo_data_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service untuk mendapatkan lokasi dari GPS phone
class PhoneGpsService {
  final loc.Location _location = loc.Location();
  
  // Public getter untuk iOS background mode
  loc.Location get location => _location;
  
  StreamSubscription<loc.LocationData>? _locationSubscription;
  final StreamController<GeoPoint> _locationController = 
      StreamController<GeoPoint>.broadcast();
  
  Stream<GeoPoint> get locationStream => _locationController.stream;
  
  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await _location.serviceEnabled();
  }
  
  /// Request location service enable
  Future<bool> requestService() async {
    return await _location.requestService();
  }
  
  /// Check permission status
  Future<loc.PermissionStatus> checkPermission() async {
    return await _location.hasPermission();
  }
  
  /// Request location permission
  Future<loc.PermissionStatus> requestPermission() async {
    return await _location.requestPermission();
  }
  
  /// Check and request all necessary permissions
  Future<bool> checkAndRequestPermission() async {
    // Check service enabled
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        print('❌ Location service not enabled');
        return false;
      }
    }
    
    // Check permission
    loc.PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) {
        print('❌ Location permission not granted');
        return false;
      }
    }
    
    print('✅ Location permission granted');
    return true;
  }
  
  /// Get current location (single shot)
  Future<GeoPoint?> getCurrentLocation() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return null;
      
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      
      final locationData = await _location.getLocation();
      
      if (locationData.latitude == null || locationData.longitude == null) {
        return null;
      }
      
      return GeoPoint(
        latitude: locationData.latitude!,
        longitude: locationData.longitude!,
        altitude: locationData.altitude,
        accuracy: locationData.accuracy,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          locationData.time?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      print('❌ Error getting current location: $e');
      return null;
    }
  }
  
  /// Start continuous location tracking
  Future<bool> startTracking({
    loc.LocationAccuracy accuracy = loc.LocationAccuracy.high,
    int interval = 1000,
    double distanceFilter = 0,
  }) async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return false;
      
      // Configure location settings
      await _location.changeSettings(
        accuracy: accuracy,
        interval: interval,
        distanceFilter: distanceFilter,
      );
      
      // Cancel existing subscription
      await _locationSubscription?.cancel();
      
      // Start new subscription
      _locationSubscription = _location.onLocationChanged.listen(
        (locationData) {
          if (locationData.latitude != null && locationData.longitude != null) {
            final point = GeoPoint(
              latitude: locationData.latitude!,
              longitude: locationData.longitude!,
              altitude: locationData.altitude,
              accuracy: locationData.accuracy,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                locationData.time?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
              ),
            );
            _locationController.add(point);
          }
        },
        onError: (error) {
          print('❌ Location stream error: $error');
        },
      );
      
      print('✅ Phone GPS tracking started');
      return true;
      
    } catch (e) {
      print('❌ Error starting GPS tracking: $e');
      return false;
    }
  }
  
  /// Stop location tracking
  Future<void> stopTracking() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    print('⏹️ Phone GPS tracking stopped');
  }
  
  /// Enable background mode (iOS only)
  Future<void> enableBackgroundMode(bool enable) async {
    if (Platform.isIOS) {
      await _location.enableBackgroundMode(enable: enable);
      print('📱 iOS background mode: ${enable ? "enabled" : "disabled"}');
    }
  }
  
  /// Dispose resources
  void dispose() {
    _locationSubscription?.cancel();
    _locationController.close();
  }
}
