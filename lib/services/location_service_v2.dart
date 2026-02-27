import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/geo_data_model.dart';
import 'dart:math' show cos, sqrt, asin, sin, atan, atan2;
import 'background/notification_service.dart';
import 'background/permission_service.dart';
import 'background/background_tracking_service.dart';
import 'background/phone_gps_service.dart';

// Enums untuk Location Provider
enum LocationProvider { phone, emlid }
enum CoordinateFormat { nmea, llh, xyz }
enum FixQuality { any, autonomous, float, fix }


class LocationServiceV2 {
  // Singleton pattern
  static final LocationServiceV2 _instance = LocationServiceV2._internal();
  factory LocationServiceV2() => _instance;
  LocationServiceV2._internal();
  
  // Services
  final PhoneGpsService _phoneGps = PhoneGpsService();
  final BackgroundTrackingService _backgroundTracking = BackgroundTrackingService();
  
  // Persistent tracking state
  bool _isActivelyTracking = false;
  bool get isActivelyTracking => _isActivelyTracking;
  
  List<GeoPoint> _activeTrackingPoints = [];
  List<GeoPoint> get activeTrackingPoints => _activeTrackingPoints;
  
  // Location provider settings
  LocationProvider _currentProvider = LocationProvider.phone;
  FixQuality _requiredFixQuality = FixQuality.any;
  CoordinateFormat _coordinateFormat = CoordinateFormat.llh;
  
  // Emlid connection
  Socket? _emlidSocket;
  final StreamController<GeoPoint> _emlidLocationController = 
      StreamController<GeoPoint>.broadcast();
  final StreamController<String> _consoleController = 
      StreamController<String>.broadcast();
  
  Stream<GeoPoint> get emlidLocationStream => _emlidLocationController.stream;
  Stream<String> get consoleStream => _consoleController.stream;
  
  bool _isEmlidConnected = false;
  String _emlidBuffer = '';
  DateTime? _lastEmlidDataTime;
  
  // Getters
  LocationProvider get currentProvider => _currentProvider;
  FixQuality get currentFixQuality => _requiredFixQuality;
  bool get isEmlidConnected => _isEmlidConnected;
  DateTime? get lastEmlidDataTime => _lastEmlidDataTime;
  
  bool get isEmlidStreaming {
    if (!_isEmlidConnected || _lastEmlidDataTime == null) return false;
    return DateTime.now().difference(_lastEmlidDataTime!).inSeconds < 10;
  }
  
  // ============================================================================
  // INITIALIZATION
  // ============================================================================
Future<bool> initialize() async {
  print('Initializing LocationService...');
 
  try {
    // 1. Check if location service is enabled
    print('Checking location service...');
    final serviceEnabled = await PermissionService.isLocationServiceEnabled();
    
    if (!serviceEnabled) {
      print('❌ Location service is disabled');
      throw Exception('Location service is disabled. Please enable GPS in device settings.');
    }
    print('✅ Location service is enabled');
    
    // 2. Request permissions
    print('Requesting permissions...');
    final hasPermission = await PermissionService.requestAllPermissions();
    
    if (!hasPermission) {
      print('❌ Failed to get required permissions');
      
      // Print detailed status for debugging
      final status = await PermissionService.getDetailedStatus();
      print('📊 Detailed Status: $status');
      
      throw Exception('Location permissions not granted. Please allow location access in Settings.');
    }
    print('✅ Permissions granted');
    
    // 3. Verify permission again
    print('📍 Step 3/5: Verifying permissions...');
    final hasLocationPermission = await PermissionService.hasLocationPermission();
    
    if (!hasLocationPermission) {
      print('❌ Permission verification failed');
      throw Exception('Permission verification failed after grant');
    }
    print('✅ Permissions verified');
    
    // 4. Initialize notification service
    print('📍 Step 4/5: Initializing notification service...');
    try {
      await NotificationService.initialize();
      print('✅ Notification service initialized');
    } catch (e) {
      print('⚠️ Notification service initialization failed: $e');
      // Continue anyway - not critical for iOS
    }
    
    // 5. Initialize background tracking service
    print('📍 Step 5/5: Initializing background tracking...');
    try {
      await _backgroundTracking.initialize();
      print('✅ Background tracking service initialized');
    } catch (e) {
      print('⚠️ Background tracking initialization failed: $e');
      // Continue anyway - can still use foreground tracking
    }
    
    // 6. Load saved settings
    await loadLocationSettings();
    print('✅ Settings loaded');
    print('✅ LocationService initialized successfully');

    if (_currentProvider == LocationProvider.phone) {
      await _phoneGps.startTracking();
      print('✅ Started foreground GPS tracking');
    }


    return true;
    
  } catch (e, stackTrace) {
    print('❌ ========================================');
    print('❌ Failed to initialize LocationServiceV2');
    print('❌ Error: $e');
    print('❌ ========================================');
    print('Stack trace: $stackTrace');
    return false;
  }
}
  
  // ============================================================================
  // PERMISSION & SERVICE CHECK
  // ============================================================================
  
  Future<bool> checkAndRequestPermission() async {
    return await PermissionService.requestAllPermissions();
  }
  
  Future<bool> isLocationServiceEnabled() async {
    return await _phoneGps.isLocationServiceEnabled();
  }
  
  // ============================================================================
  // TRACKING STATE MANAGEMENT
  // ============================================================================
  
  void startActiveTracking() {
    _isActivelyTracking = true;
    _activeTrackingPoints.clear();
    print('✅ Active tracking started');
  }
  
  void pauseActiveTracking() {
    _isActivelyTracking = true; // Still tracking, just paused
    print('⏸️ Active tracking paused');
  }
  
  void resumeActiveTracking() {
    _isActivelyTracking = true;
    print('▶️ Active tracking resumed');
  }
  
  void stopActiveTracking() {
    _isActivelyTracking = false;
    print('⏹️ Active tracking stopped');
  }
  
  void addTrackingPoint(GeoPoint point) {
    if (_isActivelyTracking) {
      _activeTrackingPoints.add(point);
    }
  }
  
  void clearTrackingPoints() {
    _activeTrackingPoints.clear();
  }
  
  // ============================================================================
  // LOCATION ACQUISITION
  // ============================================================================
  
  /// Get current location (single shot)
  Future<GeoPoint?> getCurrentLocation() async {
    if (_currentProvider == LocationProvider.emlid && _isEmlidConnected) {
      // Return last known Emlid location
      return await _backgroundTracking.getLastSavedLocation();
    }
    
    // Use phone GPS
    return await _phoneGps.getCurrentLocation();
  }
  
  /// Get continuous location stream based on active provider
  Stream<GeoPoint> getActiveLocationStream() {
    if (_currentProvider == LocationProvider.emlid && _isEmlidConnected) {
      return trackEmlidLocation();
    }
    return trackLocation();
  }
  
  /// Track location using phone GPS (foreground)
  Stream<GeoPoint> trackLocation() {
    return _phoneGps.locationStream;
  }
  
  /// Start foreground location tracking
  Future<bool> startForegroundTracking() async {
    return await _phoneGps.startTracking();
  }
  
  /// Stop foreground location tracking
  Future<void> stopForegroundTracking() async {
    await _phoneGps.stopTracking();
  }
  
  // ============================================================================
  // BACKGROUND TRACKING
  // ============================================================================
  
  // 🔧 FIX: Tambahkan subscription variable untuk cleanup
  StreamSubscription<GeoPoint>? _backgroundTrackingSubscription;
  
  /// Start background location tracking
  Future<bool> startBackgroundTracking() async {
    print('═══════════════════════════════════════');
    print('📍 Starting background tracking...');
    print('═══════════════════════════════════════');
    
    try {
      // 🔧 FIX: Cancel existing subscription untuk avoid duplicate
      await _backgroundTrackingSubscription?.cancel();
      _backgroundTrackingSubscription = null;
      
      // Ensure initialized
      if (!_backgroundTracking.isRunning) {
        print('🚀 Background service not running, starting...');
        
        final success = await _backgroundTracking.start();
        if (!success) {
          print('❌ Failed to start background tracking service');
          print('═══════════════════════════════════════');
          return false;
        }
        
        print('✅ Background service started successfully');
      } else {
        print('✅ Background service already running');
      }
      
      // 🔧 FIX: HANYA SATU listener, simpan subscription untuk cleanup
      print('📡 Setting up location stream listener...');
      _backgroundTrackingSubscription = _backgroundTracking.locationStream.listen(
        (point) {
          print('📥 RECEIVED in LocationServiceV2:');
          print('   Lat: ${point.latitude}');
          print('   Lon: ${point.longitude}');
          print('   Time: ${point.timestamp}');
          
          addTrackingPoint(point);
          
          // Debug: Print total points
          print('✅ Added to tracking points (Total: ${_activeTrackingPoints.length})');
        },
        onError: (error) {
          print('❌ Error in background location stream: $error');
        },
        cancelOnError: false,
      );
      
      print('✅ Background tracking listener setup complete');
      print('═══════════════════════════════════════');
      return true;
      
    } catch (e) {
      print('❌ Error starting background tracking: $e');
      print('═══════════════════════════════════════');
      return false;
    }
  }
  
  /// Send heartbeat to background service to keep it alive
  void sendHeartbeat() {
    try {
      _backgroundTracking.sendHeartbeat();
    } catch (e) {
      print('❌ Error sending heartbeat: $e');
    }
  }
  
  
  /// Stop background location tracking
  Future<void> stopBackgroundTracking() async {
    print('═══════════════════════════════════════');
    print('⏹️ Stopping background tracking...');
    print('═══════════════════════════════════════');
    
    // 🔧 FIX: Cancel subscription first
    await _backgroundTrackingSubscription?.cancel();
    _backgroundTrackingSubscription = null;
    print('✅ Subscription cancelled');
    
    // Stop background service
    await _backgroundTracking.stop();
    print('✅ Background service stopped');
    print('═══════════════════════════════════════');
  }
  
  /// Pause background tracking
  Future<void> pauseBackgroundTracking() async {
    await _backgroundTracking.pause();
  }
  
  /// Resume background tracking
  Future<void> resumeBackgroundTracking() async {
    await _backgroundTracking.resume();
  }
  
  /// Get background location stream
  Stream<GeoPoint> get backgroundLocationStream => 
      _backgroundTracking.locationStream;
  
  // ============================================================================
  // LOCATION PROVIDER SETTINGS
  // ============================================================================
  
  Future<void> setLocationProvider({
    required LocationProvider provider,
    required FixQuality requiredFixQuality,
  }) async {
    _currentProvider = provider;
    _requiredFixQuality = requiredFixQuality;
    await _saveLocationSettings();
    print('📍 Provider set to: ${provider.name}, Quality: ${requiredFixQuality.name}');
  }
  
  Future<void> loadLocationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final providerIndex = prefs.getInt('location_provider') ?? 0;
      _currentProvider = LocationProvider.values[providerIndex];
      
      final fixQualityIndex = prefs.getInt('fix_quality') ?? 0;
      _requiredFixQuality = FixQuality.values[fixQualityIndex];
      
      print('📖 Loaded settings - Provider: ${_currentProvider.name}, Fix: ${_requiredFixQuality.name}');
    } catch (e) {
      print('❌ Failed to load location settings: $e');
      _currentProvider = LocationProvider.phone;
      _requiredFixQuality = FixQuality.any;
    }
  }
  
  Future<void> _saveLocationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('location_provider', _currentProvider.index);
      await prefs.setInt('fix_quality', _requiredFixQuality.index);
      print('💾 Saved settings');
    } catch (e) {
      print('❌ Failed to save location settings: $e');
    }
  }
  
  // ============================================================================
  // EMLID REACH GPS CONNECTION
  // ============================================================================
  
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
      print('💾 Saved Emlid settings - $host:$port');
    } catch (e) {
      print('❌ Failed to save Emlid settings: $e');
    }
  }
  
  Future<Map<String, String?>> loadEmlidConnectionSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'host': prefs.getString('emlid_host'),
        'port': prefs.getInt('emlid_port')?.toString(),
        'format': prefs.getInt('emlid_format')?.toString(),
      };
    } catch (e) {
      print('❌ Failed to load Emlid settings: $e');
      return {'host': null, 'port': null, 'format': null};
    }
  }
  
  Future<bool> connectEmlidTCP({
    required String host,
    required int port,
    required CoordinateFormat coordinateFormat,
  }) async {
    try {
      print('🔌 Connecting to Emlid at $host:$port...');
      _addConsoleLog('Connecting to $host:$port...');
      
      await disconnectEmlidTCP();
      _coordinateFormat = coordinateFormat;
      
      _emlidSocket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 30),
      );
      
      _isEmlidConnected = true;
      _addConsoleLog('✓ TCP Socket connected');
      _addConsoleLog('Format: ${coordinateFormat.name.toUpperCase()}');
      
      _emlidSocket!.setOption(SocketOption.tcpNoDelay, true);
      
      _emlidSocket!.listen(
        _handleEmlidData,
        onError: (error) {
          _addConsoleLog('✗ Socket Error: $error');
          _isEmlidConnected = false;
        },
        onDone: () {
          _addConsoleLog('✗ Connection closed');
          _isEmlidConnected = false;
        },
        cancelOnError: false,
      );
      
      // Send initialization commands
      try {
        _addConsoleLog('Sending init commands...');
        _emlidSocket!.write('\r\n');
        await _emlidSocket!.flush();
        await Future.delayed(const Duration(milliseconds: 200));
        
        _emlidSocket!.add([0x00]);
        await _emlidSocket!.flush();
        await Future.delayed(const Duration(milliseconds: 200));
        
        if (coordinateFormat == CoordinateFormat.nmea) {
          _emlidSocket!.write('\$GPGGA\r\n');
          await _emlidSocket!.flush();
          await Future.delayed(const Duration(milliseconds: 200));
        }
        
        _addConsoleLog('✓ Init commands sent');
      } catch (e) {
        _addConsoleLog('⚠ Init commands error: $e');
      }
      
      _addConsoleLog('Waiting for data...');
      await Future.delayed(const Duration(seconds: 3));
      
      if (!_isEmlidConnected) {
        throw Exception('Connection lost');
      }
      
      _addConsoleLog('✓ Connected, listening for data');
      
      await saveEmlidConnectionSettings(
        host: host,
        port: port,
        format: coordinateFormat,
      );
      
      return true;
      
    } on SocketException catch (e) {
      final errorMsg = e.message;
      _addConsoleLog('✗ SocketException: $errorMsg');
      
      if (errorMsg.contains('Connection refused') || e.osError?.errorCode == 61) {
        _addConsoleLog('→ Check Emlid settings:');
        _addConsoleLog('  1. Position Output enabled');
        _addConsoleLog('  2. TCP Server mode');
        _addConsoleLog('  3. Correct port (9090)');
      } else if (errorMsg.contains('unreachable') || e.osError?.errorCode == 51) {
        _addConsoleLog('→ Network unreachable');
        _addConsoleLog('  1. Connect to Emlid WiFi');
        _addConsoleLog('  2. Check IP: 192.168.42.1');
      }
      
      _isEmlidConnected = false;
      return false;
      
    } catch (e) {
      _addConsoleLog('✗ Error: $e');
      _isEmlidConnected = false;
      return false;
    }
  }
  
  Future<void> disconnectEmlidTCP() async {
    try {
      await _emlidSocket?.close();
      _emlidSocket = null;
      _isEmlidConnected = false;
      _emlidBuffer = '';
      _addConsoleLog('Disconnected');
    } catch (e) {
      print('❌ Error disconnecting: $e');
    }
  }
  
  Stream<GeoPoint> trackEmlidLocation() {
    if (!_isEmlidConnected) {
      throw Exception('Not connected to Emlid GPS');
    }
    return _emlidLocationController.stream;
  }
  
  void _handleEmlidData(List<int> data) {
    try {
      final text = utf8.decode(data, allowMalformed: true);
      _emlidBuffer += text;
      
      final lines = _emlidBuffer.split('\n');
      _emlidBuffer = lines.removeLast();
      
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
          _lastEmlidDataTime = DateTime.now();
          if (_meetsQualityRequirement(point)) {
            _addConsoleLog('✓ Valid position');
            _emlidLocationController.add(point);
          } else {
            _addConsoleLog('⚠ Quality below requirement');
          }
        }
      }
    } catch (e) {
      _addConsoleLog('✗ Parse error: $e');
    }
  }
  
  GeoPoint? _parseNMEA(String line) {
    try {
      if (!line.startsWith('\$GPGGA') && !line.startsWith('\$GNGGA')) {
        return null;
      }
      
      final parts = line.split(',');
      if (parts.length < 15) return null;
      
      final latStr = parts[2];
      final latDir = parts[3];
      if (latStr.isEmpty || latDir.isEmpty) return null;
      
      final latDeg = double.parse(latStr.substring(0, 2));
      final latMin = double.parse(latStr.substring(2));
      var latitude = latDeg + (latMin / 60);
      if (latDir == 'S') latitude = -latitude;
      
      final lonStr = parts[4];
      final lonDir = parts[5];
      if (lonStr.isEmpty || lonDir.isEmpty) return null;
      
      final lonDeg = double.parse(lonStr.substring(0, 3));
      final lonMin = double.parse(lonStr.substring(3));
      var longitude = lonDeg + (lonMin / 60);
      if (lonDir == 'W') longitude = -longitude;
      
      final fixQuality = int.tryParse(parts[6]) ?? 0;
      String? fixQualityStr;
      switch (fixQuality) {
        case 0: fixQualityStr = 'invalid'; break;
        case 1: fixQualityStr = 'autonomous'; break;
        case 2: fixQualityStr = 'dgps'; break;
        case 4: fixQualityStr = 'fix'; break;
        case 5: fixQualityStr = 'float'; break;
        default: fixQualityStr = 'unknown';
      }
      
      final satCount = int.tryParse(parts[7]);
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
  
  GeoPoint? _parseLLH(String line) {
    try {
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
        case 1: fixQualityStr = 'fix'; break;
        case 2: fixQualityStr = 'float'; break;
        case 5: fixQualityStr = 'autonomous'; break;
        default: fixQualityStr = 'unknown';
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
  
  GeoPoint? _parseXYZ(String line) {
    try {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 10) return null;
      
      final x = double.tryParse(parts[0]);
      final y = double.tryParse(parts[1]);
      final z = double.tryParse(parts[2]);
      final quality = int.tryParse(parts[3]);
      final satCount = int.tryParse(parts[4]);
      
      if (x == null || y == null || z == null) return null;
      
      final llh = _ecefToLLH(x, y, z);
      
      String? fixQualityStr;
      switch (quality) {
        case 1: fixQualityStr = 'fix'; break;
        case 2: fixQualityStr = 'float'; break;
        case 5: fixQualityStr = 'autonomous'; break;
        default: fixQualityStr = 'unknown';
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
  
  Map<String, double> _ecefToLLH(double x, double y, double z) {
    const double a = 6378137.0;
    const double e2 = 0.00669437999014;
    
    final p = sqrt(x * x + y * y);
    final lon = atan2(y, x) * 180 / 3.141592653589793;
    
    var lat = atan2(z, p * (1 - e2));
    var height = 0.0;
    
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
  
  void _addConsoleLog(String message) {
    final timestamp = DateTime.now();
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
                   '${timestamp.minute.toString().padLeft(2, '0')}:'
                   '${timestamp.second.toString().padLeft(2, '0')}';
    _consoleController.add('[$timeStr] $message');
  }
  
  // ============================================================================
  // CALCULATION UTILITIES
  // ============================================================================
  
  double calculateDistance(GeoPoint point1, GeoPoint point2) {
    const double earthRadius = 6371000;
    
    final lat1 = _toRadians(point1.latitude);
    final lat2 = _toRadians(point2.latitude);
    final dLat = _toRadians(point2.latitude - point1.latitude);
    final dLon = _toRadians(point2.longitude - point1.longitude);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    
    final c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }
  
  double calculateLineDistance(List<GeoPoint> points) {
    if (points.length < 2) return 0;
    
    double totalDistance = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += calculateDistance(points[i], points[i + 1]);
    }
    return totalDistance;
  }
  
  double calculatePolygonArea(List<GeoPoint> points) {
    if (points.length < 3) return 0;
    
    double area = 0;
    int n = points.length;
    
    for (int i = 0; i < n; i++) {
      int j = (i + 1) % n;
      area += points[i].latitude * points[j].longitude;
      area -= points[j].latitude * points[i].longitude;
    }
    
    area = (area.abs() / 2.0);
    const double metersPerDegree = 111320;
    return area * metersPerDegree * metersPerDegree;
  }
  
  double _toRadians(double degree) {
    return degree * (3.141592653589793 / 180.0);
  }
  
  // ============================================================================
  // DISPOSE
  // ============================================================================
  
  void dispose() {
    print('🗑️ Disposing LocationServiceV2...');
    
    // Cancel background tracking subscription
    _backgroundTrackingSubscription?.cancel();
    
    // Disconnect Emlid
    disconnectEmlidTCP();
    
    // Close controllers
    _emlidLocationController.close();
    _consoleController.close();
    
    // Dispose services
    _phoneGps.dispose();
    _backgroundTracking.dispose();
    
    print('✅ LocationServiceV2 disposed');
  }
}
