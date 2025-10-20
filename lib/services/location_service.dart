import 'package:location/location.dart' as loc;
import '../models/geo_data_model.dart';
import 'dart:math' show cos, sqrt, asin;
import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:ui';
import 'package:flutter/material.dart';

class LocationService {
  final loc.Location _location = loc.Location();
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  // Public getter for iOS background mode
  loc.Location get location => _location;
  
  // Stream controller untuk tracking points dari background
  static final StreamController<GeoPoint> _backgroundLocationController = 
      StreamController<GeoPoint>.broadcast();
  
  Stream<GeoPoint> get backgroundLocationStream => _backgroundLocationController.stream;

  // Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await _location.serviceEnabled();
  }

  // Check and request permission
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return false;
      }
    }

    loc.PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) {
        return false;
      }
    }

    return true;
  }

  // Get current location
  Future<GeoPoint?> getCurrentLocation() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return null;

      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      final locationData = await _location.getLocation();

      return GeoPoint(
        latitude: locationData.latitude!,
        longitude: locationData.longitude!,
        altitude: locationData.altitude,
        accuracy: locationData.accuracy,
        timestamp: DateTime.fromMillisecondsSinceEpoch(locationData.time!.toInt()),
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  // Initialize background service
  Future<void> initializeBackgroundService() async {
    final service = FlutterBackgroundService();
    
    // Initialize notification (Android only)
    if (Platform.isAndroid) {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );
      
      await _notifications.initialize(initializationSettings);
    }
    
    // Configure background service
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'geoform_tracking',
        initialNotificationTitle: 'GeoForm Tracking',
        initialNotificationContent: 'Tracking location...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  // Start background tracking
  Future<void> startBackgroundTracking() async {
    // Enable background location for iOS
    if (Platform.isIOS) {
      await _location.enableBackgroundMode(enable: true);
    }
    
    final service = FlutterBackgroundService();
    await initializeBackgroundService();
    await service.startService();
  }

  // Stop background tracking
  Future<void> stopBackgroundTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('stop');
    
    // Disable background location for iOS
    if (Platform.isIOS) {
      await _location.enableBackgroundMode(enable: false);
    }
  }

  // Pause background tracking
  Future<void> pauseBackgroundTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('pause');
  }

  // Resume background tracking
  Future<void> resumeBackgroundTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('resume');
  }

  // Background service entry point
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    
    final loc.Location location = loc.Location();
    StreamSubscription<loc.LocationData>? locationSubscription;
    bool isPaused = false;

    // Listen for commands from UI
    service.on('stop').listen((event) {
      locationSubscription?.cancel();
      service.stopSelf();
    });

    service.on('pause').listen((event) {
      isPaused = true;
      _updateNotification('Tracking Paused', 'Tap to resume');
    });

    service.on('resume').listen((event) {
      isPaused = false;
      _updateNotification('Tracking Active', 'Recording location...');
    });

    // Start tracking location
    locationSubscription = location.onLocationChanged.listen((locationData) {
      if (!isPaused && locationData.latitude != null && locationData.longitude != null) {
        final point = GeoPoint(
          latitude: locationData.latitude!,
          longitude: locationData.longitude!,
          altitude: locationData.altitude,
          accuracy: locationData.accuracy,
          timestamp: DateTime.fromMillisecondsSinceEpoch(locationData.time!.toInt()),
        );
        
        // Send location to UI
        service.invoke('location', {
          'latitude': point.latitude,
          'longitude': point.longitude,
          'altitude': point.altitude,
          'accuracy': point.accuracy,
          'timestamp': point.timestamp.millisecondsSinceEpoch,
        });
        
        // Also emit to stream controller
        _backgroundLocationController.add(point);
      }
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  static Future<void> _updateNotification(String title, String content) async {
    // Only show notification on Android
    if (Platform.isAndroid) {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'geoform_tracking',
        'Location Tracking',
        channelDescription: 'Shows when tracking location',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,
      );
      
      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
      );
      
      await _notifications.show(888, title, content, notificationDetails);
    }
  }

  // Start tracking location (foreground only - for old implementation)
  Stream<GeoPoint> trackLocation() {
    return _location.onLocationChanged.map((locationData) => GeoPoint(
      latitude: locationData.latitude!,
      longitude: locationData.longitude!,
      altitude: locationData.altitude,
      accuracy: locationData.accuracy,
      timestamp: DateTime.fromMillisecondsSinceEpoch(locationData.time!.toInt()),
    ));
  }

  // Calculate distance between two points (in meters)
  double calculateDistance(GeoPoint point1, GeoPoint point2) {
    const double earthRadius = 6371000; // meters
    
    final lat1 = _toRadians(point1.latitude);
    final lat2 = _toRadians(point2.latitude);
    final dLat = _toRadians(point2.latitude - point1.latitude);
    final dLon = _toRadians(point2.longitude - point1.longitude);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final c = 2 * asin(sqrt(a));
    
    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * (3.141592653589793 / 180.0);
  }

  double sin(double value) {
    return (value - (value * value * value) / 6 + (value * value * value * value * value) / 120);
  }

  double cos(double value) {
    return 1 - (value * value) / 2 + (value * value * value * value) / 24;
  }

  // Calculate total distance for a line
  double calculateLineDistance(List<GeoPoint> points) {
    if (points.length < 2) return 0;
    
    double totalDistance = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += calculateDistance(points[i], points[i + 1]);
    }
    return totalDistance;
  }

  // Calculate area for a polygon (approximate, in square meters)
  double calculatePolygonArea(List<GeoPoint> points) {
    if (points.length < 3) return 0;
    
    // Using the Shoelace formula
    double area = 0;
    int n = points.length;
    
    for (int i = 0; i < n; i++) {
      int j = (i + 1) % n;
      area += points[i].latitude * points[j].longitude;
      area -= points[j].latitude * points[i].longitude;
    }
    
    area = (area.abs() / 2.0);
    
    // Convert to approximate square meters
    // This is a rough approximation, for precise calculations use proper geospatial libraries
    const double metersPerDegree = 111320; // at equator
    return area * metersPerDegree * metersPerDegree;
  }
}
