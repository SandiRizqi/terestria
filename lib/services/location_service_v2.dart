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
import 'gps_logger_service.dart';
import 'gps_settings_service.dart';
import 'crashlytics_service.dart';
import '../utils/app_logger.dart';
import '../config/location_config.dart';

// Enums untuk Location Provider
enum LocationProvider { phone, emlid }
enum CoordinateFormat { nmea, llh, xyz }
enum FixQuality { any, autonomous, float, fix }

/// Apakah `getCurrentLocation()` harus mengembalikan titik Emlid LIVE terakhir?
///
/// Hanya benar bila provider Emlid dipilih, socket konek, data masih streaming,
/// DAN sudah ada titik Emlid yang lolos filter. Bila belum ada titik live,
/// pemanggil harus fallback ke GPS phone — BUKAN membaca prefs `last_lat`
/// (yang hanya ditulis isolate phone, bukan Emlid).
bool shouldUseLiveEmlidPoint({
  required LocationProvider provider,
  required bool isConnected,
  required bool isStreaming,
  required bool hasLastEmlidPoint,
}) =>
    provider == LocationProvider.emlid &&
    isConnected &&
    isStreaming &&
    hasLastEmlidPoint;

/// Tier kualitas untuk fix GPS phone berdasarkan akurasi (meter).
/// Phone GPS paling tinggi setara 'autonomous' (bukan RTK float/fix).
/// Mengembalikan 'autonomous' bila akurasi cukup baik, atau `null` bila belum
/// layak dianggap fix bermutu.
String? phoneFixTier(double accuracy, double goodFixThresholdMeters) =>
    accuracy <= goodFixThresholdMeters ? 'autonomous' : null;

/// Apakah [fixQuality] memenuhi [required]? (versi pure dari
/// `_meetsQualityRequirement`, dipakai untuk gating capture phone maupun Emlid.)
bool meetsFixRequirement(FixQuality required, String? fixQuality) {
  switch (required) {
    case FixQuality.any:
      return true;
    case FixQuality.autonomous:
      return fixQuality == 'autonomous' ||
          fixQuality == 'float' ||
          fixQuality == 'fix' ||
          fixQuality == 'dgps';
    case FixQuality.float:
      return fixQuality == 'float' || fixQuality == 'fix';
    case FixQuality.fix:
      return fixQuality == 'fix';
  }
}


class LocationServiceV2 {
  // Singleton pattern
  static final LocationServiceV2 _instance = LocationServiceV2._internal();
  factory LocationServiceV2() => _instance;
  LocationServiceV2._internal();
  
  // Services
  final PhoneGpsService _phoneGps = PhoneGpsService();
  final BackgroundTrackingService _backgroundTracking = BackgroundTrackingService();
  final GpsLoggerService _gpsLogger = GpsLoggerService();
  
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
  GeoPoint? _lastEmlidPoint; // titik Emlid live terakhir yang lolos filter
  
  // Getters
  LocationProvider get currentProvider => _currentProvider;
  FixQuality get currentFixQuality => _requiredFixQuality;
  bool get isEmlidConnected => _isEmlidConnected;
  DateTime? get lastEmlidDataTime => _lastEmlidDataTime;
  
  bool get isEmlidStreaming {
    if (!_isEmlidConnected || _lastEmlidDataTime == null) return false;
    return DateTime.now().difference(_lastEmlidDataTime!).inSeconds <
        GpsSettingsService().settings.emlidStaleSeconds;
  }

  /// True bila provider Emlid dipilih TAPI datanya tidak streaming (stale /
  /// belum konek). Saat ini sistem otomatis fallback ke GPS phone.
  bool get _shouldFallbackToPhone =>
      _currentProvider == LocationProvider.emlid &&
      (!_isEmlidConnected || !isEmlidStreaming);
  
  // ============================================================================
  // INITIALIZATION
  // ============================================================================
Future<bool> initialize() async {
  logDebug('Initializing LocationService...');
 
  try {
    // 1. Check if location service is enabled
    logDebug('Checking location service...');
    final serviceEnabled = await PermissionService.isLocationServiceEnabled();
    
    if (!serviceEnabled) {
      logError('❌ Location service is disabled');
      throw Exception('Location service is disabled. Please enable GPS in device settings.');
    }
    logDebug('✅ Location service is enabled');
    
    // 2. Request permissions
    logDebug('Requesting permissions...');
    final hasPermission = await PermissionService.requestAllPermissions();
    
    if (!hasPermission) {
      logError('❌ Failed to get required permissions');
      
      // Print detailed status for debugging
      final status = await PermissionService.getDetailedStatus();
      logDebug('📊 Detailed Status: $status');
      
      throw Exception('Location permissions not granted. Please allow location access in Settings.');
    }
    logDebug('✅ Permissions granted');
    
    // 3. Verify permission again
    logDebug('📍 Step 3/5: Verifying permissions...');
    final hasLocationPermission = await PermissionService.hasLocationPermission();
    
    if (!hasLocationPermission) {
      logError('❌ Permission verification failed');
      throw Exception('Permission verification failed after grant');
    }
    logDebug('✅ Permissions verified');
    
    // 4. Initialize notification service
    logDebug('📍 Step 4/5: Initializing notification service...');
    try {
      await NotificationService.initialize();
      logDebug('✅ Notification service initialized');
    } catch (e, stack) {
      logDebug('⚠️ Notification service initialization failed: $e');
      crashlytics.recordError(e, stack,
          reason: 'GPS: Notification service init failed');
      // Continue anyway - not critical for iOS
    }

    // 5. Initialize background tracking service
    logDebug('📍 Step 5/5: Initializing background tracking...');
    try {
      await _backgroundTracking.initialize();
      logDebug('✅ Background tracking service initialized');
    } catch (e, stack) {
      logDebug('⚠️ Background tracking initialization failed: $e');
      crashlytics.recordError(e, stack,
          reason: 'GPS: Background tracking service init failed');
      // Continue anyway - can still use foreground tracking
    }
    
    // 6. Load saved settings (provider + tuning GPS)
    await loadLocationSettings();
    await GpsSettingsService().initialize();
    logDebug('✅ Settings loaded');
    logDebug('✅ LocationService initialized successfully');

    if (_currentProvider == LocationProvider.phone) {
      await _phoneGps.startTracking();
      logDebug('✅ Started foreground GPS tracking');
    }


    return true;
    
  } catch (e, stackTrace) {
    logError('❌ ========================================');
    logError('❌ Failed to initialize LocationServiceV2');
    logError('❌ Error: $e');
    logError('❌ ========================================');
    logDebug('Stack trace: $stackTrace');
    crashlytics.log('GPS init failed: $e');
    crashlytics.setContext('gps_provider', _currentProvider.name);
    crashlytics.recordError(e, stackTrace,
        reason: 'GPS: LocationService initialization failed');
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
  
  Future<void> startActiveTracking() async {
    _isActivelyTracking = true;
    _activeTrackingPoints.clear();
    await _gpsLogger.startSession();
    logDebug('✅ Active tracking started');
  }
  
  void pauseActiveTracking() {
    _isActivelyTracking = true; // Still tracking, just paused
    logDebug('⏸️ Active tracking paused');
  }
  
  void resumeActiveTracking() {
    _isActivelyTracking = true;
    logDebug('▶️ Active tracking resumed');
  }
  
  Future<void> stopActiveTracking() async {
    _isActivelyTracking = false;
    await _gpsLogger.stopSession();
    logDebug('⏹️ Active tracking stopped');
  }

  void addTrackingPoint(GeoPoint point) {
    if (_isActivelyTracking) {
      _activeTrackingPoints.add(point);
      _gpsLogger.log(point);
    }
  }

  /// Expose GPS log file listing for export / debug screens.
  Future<List<File>> getGpsLogFiles() => _gpsLogger.listLogFiles();

  /// Delete logs older than [days] days (call on app startup for housekeeping).
  Future<void> cleanOldGpsLogs({int days = 30}) =>
      _gpsLogger.deleteOldLogs(days: days);
  
  void clearTrackingPoints() {
    _activeTrackingPoints.clear();
  }
  
  // ============================================================================
  // LOCATION ACQUISITION
  // ============================================================================
  
  /// Get current location (single shot)
  Future<GeoPoint?> getCurrentLocation() async {
    // Emlid live: kembalikan titik Emlid terakhir yang lolos filter — BUKAN
    // prefs `last_lat` (yang hanya ditulis isolate phone GPS, sumber salah).
    if (shouldUseLiveEmlidPoint(
      provider: _currentProvider,
      isConnected: _isEmlidConnected,
      isStreaming: isEmlidStreaming,
      hasLastEmlidPoint: _lastEmlidPoint != null,
    )) {
      return _lastEmlidPoint;
    }

    // Provider Emlid tapi stale/terputus → fallback otomatis ke GPS phone.
    if (_shouldFallbackToPhone) {
      logDebug('⚠️ Emlid stale/terputus — fallback getCurrentLocation ke phone GPS');
    }

    // Use phone GPS — lampirkan tier kualitas berbasis akurasi supaya gating
    // fix-quality tidak lagi jadi no-op untuk provider phone.
    final p = await _phoneGps.getCurrentLocation();
    if (p == null || p.fixQuality != null || p.accuracy == null) return p;
    return GeoPoint(
      latitude: p.latitude,
      longitude: p.longitude,
      altitude: p.altitude,
      accuracy: p.accuracy,
      speed: p.speed,
      timestamp: p.timestamp,
      fixQuality: phoneFixTier(p.accuracy!, LocationConfig.goodFixThresholdMeters),
      satelliteCount: p.satelliteCount,
    );
  }

  /// Apakah [point] memenuhi syarat kualitas fix yang sedang aktif?
  /// Dipakai UI capture untuk memperingatkan (bukan memblok) titik di bawah
  /// syarat. Titik phone dari stream tak membawa fixQuality → tier diturunkan
  /// dari akurasi agar syarat tidak jadi no-op untuk phone.
  bool pointMeetsCurrentRequirement(GeoPoint point) {
    final tier = point.fixQuality ??
        phoneFixTier(point.accuracy ?? double.infinity,
            LocationConfig.goodFixThresholdMeters);
    return meetsFixRequirement(_requiredFixQuality, tier);
  }

  /// Get continuous location stream based on active provider
  Stream<GeoPoint> getActiveLocationStream() {
    if (_currentProvider == LocationProvider.emlid &&
        _isEmlidConnected &&
        isEmlidStreaming) {
      return trackEmlidLocation();
    }
    // Provider Emlid tapi stale/terputus → fallback otomatis ke GPS phone
    // supaya posisi tidak beku saat Emlid berhenti mengirim data.
    if (_shouldFallbackToPhone) {
      logDebug('⚠️ Emlid stale/terputus — fallback stream ke phone GPS');
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
    logDebug('═══════════════════════════════════════');
    logDebug('📍 Starting background tracking...');
    logDebug('═══════════════════════════════════════');
    
    try {
      // 🔧 FIX: Cancel existing subscription untuk avoid duplicate
      await _backgroundTrackingSubscription?.cancel();
      _backgroundTrackingSubscription = null;
      
      // Ensure initialized
      if (!_backgroundTracking.isRunning) {
        logDebug('🚀 Background service not running, starting...');
        
        final success = await _backgroundTracking.start();
        if (!success) {
          logError('❌ Failed to start background tracking service');
          logDebug('═══════════════════════════════════════');
          return false;
        }
        
        logDebug('✅ Background service started successfully');
      } else {
        logDebug('✅ Background service already running');
      }
      
      // 🔧 FIX: HANYA SATU listener, simpan subscription untuk cleanup
      logDebug('📡 Setting up location stream listener...');
      _backgroundTrackingSubscription = _backgroundTracking.locationStream.listen(
        (point) {
          logDebug('📥 RECEIVED in LocationServiceV2:');
          logDebug('   Lat: ${point.latitude}');
          logDebug('   Lon: ${point.longitude}');
          logDebug('   Time: ${point.timestamp}');
          
          addTrackingPoint(point);
          
          // Debug: Print total points
          logDebug('✅ Added to tracking points (Total: ${_activeTrackingPoints.length})');
        },
        onError: (error) {
          logError('❌ Error in background location stream: $error');
        },
        cancelOnError: false,
      );
      
      logDebug('✅ Background tracking listener setup complete');
      logDebug('═══════════════════════════════════════');
      return true;
      
    } catch (e, stack) {
      logError('❌ Error starting background tracking: $e');
      logDebug('═══════════════════════════════════════');
      crashlytics.setContext('gps_provider', _currentProvider.name);
      crashlytics.recordError(e, stack,
          reason: 'GPS: startBackgroundTracking failed');
      return false;
    }
  }
  
  /// Send heartbeat to background service to keep it alive
  void sendHeartbeat() {
    try {
      _backgroundTracking.sendHeartbeat();
    } catch (e) {
      logError('❌ Error sending heartbeat: $e');
    }
  }
  
  
  /// Stop background location tracking
  Future<void> stopBackgroundTracking() async {
    logDebug('═══════════════════════════════════════');
    logDebug('⏹️ Stopping background tracking...');
    logDebug('═══════════════════════════════════════');
    
    // 🔧 FIX: Cancel subscription first
    await _backgroundTrackingSubscription?.cancel();
    _backgroundTrackingSubscription = null;
    logDebug('✅ Subscription cancelled');
    
    // Stop background service
    await _backgroundTracking.stop();
    logDebug('✅ Background service stopped');
    logDebug('═══════════════════════════════════════');
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
    logDebug('📍 Provider set to: ${provider.name}, Quality: ${requiredFixQuality.name}');
  }
  
  Future<void> loadLocationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final providerIndex = prefs.getInt('location_provider') ?? 0;
      _currentProvider = LocationProvider.values[providerIndex];
      
      final fixQualityIndex = prefs.getInt('fix_quality') ?? 0;
      _requiredFixQuality = FixQuality.values[fixQualityIndex];
      
      logDebug('📖 Loaded settings - Provider: ${_currentProvider.name}, Fix: ${_requiredFixQuality.name}');
    } catch (e, stack) {
      logError('❌ Failed to load location settings: $e');
      crashlytics.recordError(e, stack, reason: 'GPS: Load settings failed');
      _currentProvider = LocationProvider.phone;
      _requiredFixQuality = FixQuality.any;
    }
  }
  
  Future<void> _saveLocationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('location_provider', _currentProvider.index);
      await prefs.setInt('fix_quality', _requiredFixQuality.index);
      logDebug('💾 Saved settings');
    } catch (e) {
      logError('❌ Failed to save location settings: $e');
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
      logDebug('💾 Saved Emlid settings - $host:$port');
    } catch (e) {
      logError('❌ Failed to save Emlid settings: $e');
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
      logError('❌ Failed to load Emlid settings: $e');
      return {'host': null, 'port': null, 'format': null};
    }
  }
  
  Future<bool> connectEmlidTCP({
    required String host,
    required int port,
    required CoordinateFormat coordinateFormat,
  }) async {
    try {
      logDebug('🔌 Connecting to Emlid at $host:$port...');
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
      _lastEmlidPoint = null;
      _lastEmlidDataTime = null;
      _addConsoleLog('Disconnected');
    } catch (e) {
      logError('❌ Error disconnecting: $e');
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
            _lastEmlidPoint = point; // sumber getCurrentLocation utk Emlid live
            _emlidLocationController.add(point);
            _gpsLogger.log(point);
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
  
  bool _meetsQualityRequirement(GeoPoint point) =>
      point.fixQuality != null &&
      meetsFixRequirement(_requiredFixQuality, point.fixQuality);
  
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
    logDebug('🗑️ Disposing LocationServiceV2...');

    // Cancel background tracking subscription
    _backgroundTrackingSubscription?.cancel();

    // Disconnect Emlid
    disconnectEmlidTCP();

    // Flush and close GPS logger
    _gpsLogger.stopSession();

    // Close controllers
    _emlidLocationController.close();
    _consoleController.close();

    // Dispose services
    _phoneGps.dispose();
    _backgroundTracking.dispose();

    logDebug('✅ LocationServiceV2 disposed');
  }
}
