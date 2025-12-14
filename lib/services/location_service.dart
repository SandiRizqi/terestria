import 'package:location/location.dart' as loc;
import '../models/geo_data_model.dart';
import 'dart:math' show cos, sqrt, asin;
import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Enums untuk Location Provider
enum LocationProvider { phone, emlid }
enum CoordinateFormat { nmea, llh, xyz }
enum FixQuality { any, autonomous, float, fix }

class LocationService {
  final loc.Location _location = loc.Location();
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  // Public getter for iOS background mode
  loc.Location get location => _location;
  
  // 🔧 NEW: Singleton instance for persistent tracking state
  static LocationService? _instance;
  factory LocationService() {
    _instance ??= LocationService._internal();
    return _instance!;
  }
  LocationService._internal();
  
  // 🔧 NEW: Persistent tracking state across screen navigation
  bool _isActivelyTracking = false;
  bool get isActivelyTracking => _isActivelyTracking;
  
  List<GeoPoint> _activeTrackingPoints = [];
  List<GeoPoint> get activeTrackingPoints => _activeTrackingPoints;
  
  void startActiveTracking() {
    _isActivelyTracking = true;
    _activeTrackingPoints.clear();
    print('✅ Active tracking started (persistent)');
  }
  
  void pauseActiveTracking() {
    _isActivelyTracking = true; // Still tracking, just paused
    print('⏸️ Active tracking paused (persistent)');
  }
  
  void resumeActiveTracking() {
    _isActivelyTracking = true;
    print('▶️ Active tracking resumed (persistent)');
  }
  
  void stopActiveTracking() {
    _isActivelyTracking = false;
    print('⏹️ Active tracking stopped (persistent)');
  }
  
  void addTrackingPoint(GeoPoint point) {
    if (_isActivelyTracking) {
      _activeTrackingPoints.add(point);
    }
  }
  
  void clearTrackingPoints() {
    _activeTrackingPoints.clear();
  }
  
  // Stream controller untuk tracking points dari background
  static final StreamController<GeoPoint> _backgroundLocationController = 
      StreamController<GeoPoint>.broadcast();
  
  Stream<GeoPoint> get backgroundLocationStream => _backgroundLocationController.stream;

  // Emlid TCP connection
  Socket? _emlidSocket;
  final StreamController<GeoPoint> _emlidLocationController = StreamController<GeoPoint>.broadcast();
  final StreamController<String> _consoleController = StreamController<String>.broadcast();
  
  Stream<GeoPoint> get emlidLocationStream => _emlidLocationController.stream;
  Stream<String> get consoleStream => _consoleController.stream;
  
  bool _isEmlidConnected = false;
  LocationProvider _currentProvider = LocationProvider.phone;
  FixQuality _requiredFixQuality = FixQuality.any;
  CoordinateFormat _coordinateFormat = CoordinateFormat.llh;
  
  String _emlidBuffer = '';

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

  // Get current location based on selected provider
  Future<GeoPoint?> getCurrentLocation() async {
    if (_currentProvider == LocationProvider.emlid && _isEmlidConnected) {
      // Return last known Emlid location
      return null; // Use stream instead for Emlid
    }
    
    // Use phone GPS
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

  // Set location provider and save to preferences
  Future<void> setLocationProvider({
    required LocationProvider provider,
    required FixQuality requiredFixQuality,
  }) async {
    _currentProvider = provider;
    _requiredFixQuality = requiredFixQuality;
    
    // Save to SharedPreferences
    await _saveLocationSettings();
  }
  
  // Load location settings from SharedPreferences
  Future<void> loadLocationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load provider
      final providerIndex = prefs.getInt('location_provider') ?? 0;
      _currentProvider = LocationProvider.values[providerIndex];
      
      // Load fix quality
      final fixQualityIndex = prefs.getInt('fix_quality') ?? 0;
      _requiredFixQuality = FixQuality.values[fixQualityIndex];
      
      print('DEBUG: Loaded settings - Provider: ${_currentProvider.name}, Fix: ${_requiredFixQuality.name}');
    } catch (e) {
      print('ERROR: Failed to load location settings: $e');
      // Use defaults if loading fails
      _currentProvider = LocationProvider.phone;
      _requiredFixQuality = FixQuality.any;
    }
  }
  
  // Save location settings to SharedPreferences
  Future<void> _saveLocationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('location_provider', _currentProvider.index);
      await prefs.setInt('fix_quality', _requiredFixQuality.index);
      print('DEBUG: Saved settings - Provider: ${_currentProvider.name}, Fix: ${_requiredFixQuality.name}');
    } catch (e) {
      print('ERROR: Failed to save location settings: $e');
    }
  }
  
  // Get current provider (for UI)
  LocationProvider get currentProvider => _currentProvider;
  
  // Get current fix quality (for UI)
  FixQuality get currentFixQuality => _requiredFixQuality;
  
  // Check if Emlid is connected and streaming data
  bool get isEmlidConnected => _isEmlidConnected;
  
  // Get last received Emlid location (for checking if data is flowing)
  DateTime? _lastEmlidDataTime;
  DateTime? get lastEmlidDataTime => _lastEmlidDataTime;
  
  // Check if Emlid data is actively streaming (received data in last 10 seconds)
  bool get isEmlidStreaming {
    if (!_isEmlidConnected || _lastEmlidDataTime == null) return false;
    return DateTime.now().difference(_lastEmlidDataTime!).inSeconds < 10;
  }
  
  // Save Emlid connection settings
  Future<void> saveEmlidConnectionSettings({
    required String host,
    required int port,
    required CoordinateFormat format,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('emlid_host', host);
      await prefs.setInt('emlid_port', port);
      await prefs.setInt('emlid_format', format.index);
      print('DEBUG: Saved Emlid settings - host=$host, port=$port, format=${format.name}');
    } catch (e) {
      print('ERROR: Failed to save Emlid settings: $e');
    }
  }
  
  // Load Emlid connection settings
  Future<Map<String, String?>> loadEmlidConnectionSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'host': prefs.getString('emlid_host'),
        'port': prefs.getInt('emlid_port')?.toString(),
        'format': prefs.getInt('emlid_format')?.toString(),
      };
    } catch (e) {
      print('ERROR: Failed to load Emlid settings: $e');
      return {'host': null, 'port': null, 'format': null};
    }
  }

  // Connect to Emlid via TCP
  Future<bool> connectEmlidTCP({
    required String host,
    required int port,
    required CoordinateFormat coordinateFormat,
  }) async {
    try {
      print('DEBUG LocationService: connectEmlidTCP called with host=$host, port=$port');
      _addConsoleLog('Connecting to $host:$port...');
      
      // Close existing connection if any
      await disconnectEmlidTCP();
      
      _coordinateFormat = coordinateFormat;
      
      // Connect with longer timeout
      _emlidSocket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 30),
      );
      
      _isEmlidConnected = true;
      _addConsoleLog('✓ TCP Socket connected');
      _addConsoleLog('Format: ${coordinateFormat.name.toUpperCase()}');
      
      // Set socket options for better performance
      _emlidSocket!.setOption(SocketOption.tcpNoDelay, true);
      
      // Listen to data stream FIRST before sending any commands
      _emlidSocket!.listen(
        _handleEmlidData,
        onError: (error) {
          _addConsoleLog('✗ Socket Error: $error');
          print('DEBUG: Socket error detail: $error');
          _isEmlidConnected = false;
        },
        onDone: () {
          _addConsoleLog('✗ Connection closed by server');
          print('DEBUG: Connection done/closed');
          _isEmlidConnected = false;
        },
        cancelOnError: false,
      );
      
      // Try sending various initialization commands that might trigger data streaming
      // Many GPS receivers need a "wake up" command
      try {
        _addConsoleLog('Sending initialization commands...');
        
        // Strategy 1: Send newline (some servers need this)
        _emlidSocket!.write('\r\n');
        await _emlidSocket!.flush();
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Strategy 2: Send empty byte
        _emlidSocket!.add([0x00]);
        await _emlidSocket!.flush();
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Strategy 3: NMEA-style query (if NMEA format)
        if (coordinateFormat == CoordinateFormat.nmea) {
          _emlidSocket!.write('\$GPGGA\r\n');
          await _emlidSocket!.flush();
          await Future.delayed(const Duration(milliseconds: 200));
        }
        
        _addConsoleLog('✓ Init commands sent');
      } catch (e) {
        _addConsoleLog('⚠ Could not send init commands: $e');
        print('DEBUG: Init command error: $e');
        // Continue anyway, maybe server streams automatically
      }
      
      _addConsoleLog('Waiting for data stream...');
      _addConsoleLog('(If no data, check Emlid Position Output is enabled)');
      
      // Wait a bit to see if data starts coming
      await Future.delayed(const Duration(seconds: 3));
      
      if (!_isEmlidConnected) {
        throw Exception('Connection lost immediately after connect');
      }
      
      _addConsoleLog('✓ Connection established, listening for data');
      
      // Save successful connection settings
      await saveEmlidConnectionSettings(
        host: host,
        port: port,
        format: coordinateFormat,
      );
      
      return true;
      
    } on SocketException catch (e) {
      final errorMsg = e.message;
      _addConsoleLog('✗ SocketException: $errorMsg');
      print('DEBUG: SocketException - $errorMsg, osError: ${e.osError}');
      
      // Provide helpful error messages based on error type
      if (errorMsg.contains('Connection refused') || e.osError?.errorCode == 61) {
        _addConsoleLog('→ Server refused connection. Check:');
        _addConsoleLog('  1. Is Emlid at IP $host?');
        _addConsoleLog('  2. Is port $port correct (you set 9090)?');
        _addConsoleLog('  3. Is Position Output enabled in ReachView?');
        _addConsoleLog('  4. Is Output Format set to TCP Server?');
        _addConsoleLog('  5. Are you connected to Emlid WiFi?');
      } else if (errorMsg.contains('Network is unreachable') || e.osError?.errorCode == 51) {
        _addConsoleLog('→ Network unreachable. Check:');
        _addConsoleLog('  1. WiFi connection to Emlid');
        _addConsoleLog('  2. Your phone IP should be 192.168.42.x');
        _addConsoleLog('  3. Emlid IP should be 192.168.42.1');
      } else if (errorMsg.contains('timeout') || errorMsg.contains('timed out')) {
        _addConsoleLog('→ Connection timeout. Check:');
        _addConsoleLog('  1. Emlid device is powered on');
        _addConsoleLog('  2. Emlid WiFi is broadcasting');
        _addConsoleLog('  3. IP address is reachable (ping $host)');
      } else if (e.osError?.errorCode == 65) {
        _addConsoleLog('→ No route to host. Check:');
        _addConsoleLog('  1. You are connected to Emlid WiFi');
        _addConsoleLog('  2. IP address is correct (default: 192.168.42.1)');
      }
      
      _isEmlidConnected = false;
      return false;
    } catch (e) {
      _addConsoleLog('✗ Unexpected error: $e');
      print('DEBUG: Unexpected error - $e');
      _isEmlidConnected = false;
      return false;
    }
  }

  // Disconnect from Emlid
  Future<void> disconnectEmlidTCP() async {
    try {
      await _emlidSocket?.close();
      _emlidSocket = null;
      _isEmlidConnected = false;
      _emlidBuffer = '';
      _addConsoleLog('Disconnected');
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }

  // Handle incoming data from Emlid
  void _handleEmlidData(List<int> data) {
    try {
      // Log raw data untuk debug
      print('DEBUG: Received ${data.length} bytes');
      
      final text = utf8.decode(data, allowMalformed: true);
      print('DEBUG: Decoded text: ${text.substring(0, text.length > 100 ? 100 : text.length)}...');
      
      _emlidBuffer += text;
      
      // Process complete lines
      final lines = _emlidBuffer.split('\n');
      _emlidBuffer = lines.removeLast(); // Keep incomplete line in buffer
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        _addConsoleLog('< ${line.trim()}');
        
        GeoPoint? point;
        
        switch (_coordinateFormat) {
          case CoordinateFormat.nmea:
            point = _parseNMEA(line);
            break;
          case CoordinateFormat.llh:
            point = _parseLLH(line);
            break;
          case CoordinateFormat.xyz:
            point = _parseXYZ(line);
            break;
        }
        
        if (point != null) {
          print('DEBUG: Parsed point: lat=${point.latitude}, lon=${point.longitude}, fix=${point.fixQuality}');
          _lastEmlidDataTime = DateTime.now(); // Update last data time
          if (_meetsQualityRequirement(point)) {
            _addConsoleLog('✓ Valid position received');
            _emlidLocationController.add(point);
          } else {
            _addConsoleLog('⚠ Position quality below requirement');
          }
        } else {
          print('DEBUG: Failed to parse line: $line');
        }
      }
    } catch (e) {
      _addConsoleLog('✗ Parse error: $e');
      print('DEBUG: Parse error detail: $e');
    }
  }

  // Parse NMEA format (GGA sentence)
  GeoPoint? _parseNMEA(String line) {
    try {
      if (!line.startsWith('\$GPGGA') && !line.startsWith('\$GNGGA')) {
        return null;
      }
      
      final parts = line.split(',');
      if (parts.length < 15) return null;
      
      // Parse latitude
      final latStr = parts[2];
      final latDir = parts[3];
      if (latStr.isEmpty || latDir.isEmpty) return null;
      
      final latDeg = double.parse(latStr.substring(0, 2));
      final latMin = double.parse(latStr.substring(2));
      var latitude = latDeg + (latMin / 60);
      if (latDir == 'S') latitude = -latitude;
      
      // Parse longitude
      final lonStr = parts[4];
      final lonDir = parts[5];
      if (lonStr.isEmpty || lonDir.isEmpty) return null;
      
      final lonDeg = double.parse(lonStr.substring(0, 3));
      final lonMin = double.parse(lonStr.substring(3));
      var longitude = lonDeg + (lonMin / 60);
      if (lonDir == 'W') longitude = -longitude;
      
      // Parse fix quality
      final fixQuality = int.tryParse(parts[6]) ?? 0;
      String? fixQualityStr;
      switch (fixQuality) {
        case 0:
          fixQualityStr = 'invalid';
          break;
        case 1:
          fixQualityStr = 'autonomous';
          break;
        case 2:
          fixQualityStr = 'dgps';
          break;
        case 4:
          fixQualityStr = 'fix';
          break;
        case 5:
          fixQualityStr = 'float';
          break;
        default:
          fixQualityStr = 'unknown';
      }
      
      // Parse satellite count
      final satCount = int.tryParse(parts[7]);
      
      // Parse altitude
      final altitude = double.tryParse(parts[9]);
      
      return GeoPoint(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        timestamp: DateTime.now(),
        fixQuality: fixQualityStr,
        satelliteCount: satCount,
      );
    } catch (e) {
      _addConsoleLog('✗ NMEA parse error: $e');
      return null;
    }
  }

  // Parse LLH format (Latitude Longitude Height)
  GeoPoint? _parseLLH(String line) {
    try {
      // Expected format: lat lon height Q ns sdn sde sdu age ratio
      // Example: 47.1234567 8.9876543 456.789 1 12 0.010 0.012 0.015 1.5 5.2
      
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 10) return null;
      
      final latitude = double.tryParse(parts[0]);
      final longitude = double.tryParse(parts[1]);
      final altitude = double.tryParse(parts[2]);
      final quality = int.tryParse(parts[3]);
      final satCount = int.tryParse(parts[4]);
      
      if (latitude == null || longitude == null) return null;
      
      String? fixQualityStr;
      switch (quality) {
        case 1:
          fixQualityStr = 'fix';
          break;
        case 2:
          fixQualityStr = 'float';
          break;
        case 5:
          fixQualityStr = 'autonomous';
          break;
        default:
          fixQualityStr = 'unknown';
      }
      
      return GeoPoint(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        timestamp: DateTime.now(),
        fixQuality: fixQualityStr,
        satelliteCount: satCount,
      );
    } catch (e) {
      _addConsoleLog('✗ LLH parse error: $e');
      return null;
    }
  }

  // Parse XYZ format (ECEF coordinates)
  GeoPoint? _parseXYZ(String line) {
    try {
      // Expected format: x y z Q ns sdn sde sdu age ratio
      // Convert ECEF to LLH
      
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 10) return null;
      
      final x = double.tryParse(parts[0]);
      final y = double.tryParse(parts[1]);
      final z = double.tryParse(parts[2]);
      final quality = int.tryParse(parts[3]);
      final satCount = int.tryParse(parts[4]);
      
      if (x == null || y == null || z == null) return null;
      
      // Convert ECEF to LLH
      final llh = _ecefToLLH(x, y, z);
      
      String? fixQualityStr;
      switch (quality) {
        case 1:
          fixQualityStr = 'fix';
          break;
        case 2:
          fixQualityStr = 'float';
          break;
        case 5:
          fixQualityStr = 'autonomous';
          break;
        default:
          fixQualityStr = 'unknown';
      }
      
      return GeoPoint(
        latitude: llh['lat']!,
        longitude: llh['lon']!,
        altitude: llh['height']!,
        timestamp: DateTime.now(),
        fixQuality: fixQualityStr,
        satelliteCount: satCount,
      );
    } catch (e) {
      _addConsoleLog('✗ XYZ parse error: $e');
      return null;
    }
  }

  // Convert ECEF to LLH
  Map<String, double> _ecefToLLH(double x, double y, double z) {
    const double a = 6378137.0; // WGS84 semi-major axis
    const double e2 = 0.00669437999014; // First eccentricity squared
    
    final p = sqrt(x * x + y * y);
    final lon = atan2(y, x) * 180 / 3.141592653589793;
    
    var lat = atan2(z, p * (1 - e2));
    var height = 0.0;
    
    // Iterate to improve accuracy
    for (var i = 0; i < 5; i++) {
      final sinLat = sin(lat);
      final N = a / sqrt(1 - e2 * sinLat * sinLat);
      height = p / cos(lat) - N;
      lat = atan2(z, p * (1 - e2 * N / (N + height)));
    }
    
    return {
      'lat': lat * 180 / 3.141592653589793,
      'lon': lon,
      'height': height,
    };
  }

  // Check if position meets quality requirement
  bool _meetsQualityRequirement(GeoPoint point) {
    if (point.fixQuality == null) return false;
    
    switch (_requiredFixQuality) {
      case FixQuality.any:
        return true;
      case FixQuality.autonomous:
        return point.fixQuality == 'autonomous' ||
               point.fixQuality == 'float' ||
               point.fixQuality == 'fix' ||
               point.fixQuality == 'dgps';
      case FixQuality.float:
        return point.fixQuality == 'float' || point.fixQuality == 'fix';
      case FixQuality.fix:
        return point.fixQuality == 'fix';
    }
  }

  // Add console log
  void _addConsoleLog(String message) {
    final timestamp = DateTime.now();
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
                   '${timestamp.minute.toString().padLeft(2, '0')}:'
                   '${timestamp.second.toString().padLeft(2, '0')}';
    _consoleController.add('[$timeStr] $message');
  }

  // Track location from Emlid
  Stream<GeoPoint> trackEmlidLocation() {
    if (!_isEmlidConnected) {
      throw Exception('Not connected to Emlid GPS');
    }
    return _emlidLocationController.stream;
  }

  // Get active location stream based on provider
  Stream<GeoPoint> getActiveLocationStream() {
    if (_currentProvider == LocationProvider.emlid && _isEmlidConnected) {
      return trackEmlidLocation();
    }
    return trackLocation();
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

  double atan2(double y, double x) {
    if (x > 0) {
      return atan(y / x);
    } else if (x < 0 && y >= 0) {
      return atan(y / x) + 3.141592653589793;
    } else if (x < 0 && y < 0) {
      return atan(y / x) - 3.141592653589793;
    } else if (x == 0 && y > 0) {
      return 3.141592653589793 / 2;
    } else if (x == 0 && y < 0) {
      return -3.141592653589793 / 2;
    }
    return 0; // x == 0 && y == 0
  }

  double atan(double x) {
    // Taylor series approximation
    if (x.abs() <= 1) {
      return x - (x * x * x) / 3 + (x * x * x * x * x) / 5;
    } else {
      return (3.141592653589793 / 2) - atan(1 / x);
    }
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

  // Dispose resources
  void dispose() {
    disconnectEmlidTCP();
    _emlidLocationController.close();
    _consoleController.close();
  }
}
