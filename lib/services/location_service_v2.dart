import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/geo_data_model.dart';
import 'dart:math' as math;
import 'dart:math' show cos, sqrt, asin, sin;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/map/tools/measure_math.dart';
import 'background/notification_service.dart';
import 'background/permission_service.dart';
import 'background/background_tracking_service.dart';
import 'background/phone_gps_service.dart';
import 'gps/emlid_parsers.dart';
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


/// Ringkasan status Emlid untuk UI.
@immutable
class EmlidStatus {
  final bool connected;
  final bool reconnecting;
  final int reconnectAttempt;

  /// Kualitas fix terakhir yang DITERIMA dari receiver (bisa di bawah syarat).
  final String? lastQuality;

  /// Fix terakhir di bawah syarat kualitas → titik TIDAK direkam.
  final bool belowRequirement;
  final String requiredQuality;

  const EmlidStatus({
    this.connected = false,
    this.reconnecting = false,
    this.reconnectAttempt = 0,
    this.lastQuality,
    this.belowRequirement = false,
    this.requiredQuality = 'any',
  });
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

  // Koneksi ulang otomatis & diagnosis.
  NmeaStreamParser _nmeaParser = NmeaStreamParser();
  bool _autoReconnect = false; // aktif sesudah konek sukses; mati saat Disconnect
  Timer? _reconnectTimer;
  Timer? _watchdog;
  int _reconnectAttempt = 0;
  int _socketGen = 0; // generasi socket; event socket lama diabaikan
  String? _lastHost;
  int? _lastPort;
  DateTime? _lastEmlidBytesAt;
  int _bytesSinceConnect = 0;
  int _positionsSinceConnect = 0;
  String? _lastReceivedQuality;
  bool _belowRequirement = false;

  /// Status Emlid untuk banner UI (tersambung / menyambung ulang / kualitas
  /// di bawah syarat sehingga titik tidak direkam).
  final ValueNotifier<EmlidStatus> emlidStatus =
      ValueNotifier<EmlidStatus>(const EmlidStatus());
  
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
/// [requestBackground] false = izin lokasi latar belakang tidak diminta
/// (user memilih "Not now" pada penjelasan izin); GPS foreground tetap jalan.
Future<bool> initialize({bool requestBackground = true}) async {
  logDebug('Initializing LocationService...');
 
  try {
    // 1. Check if location service is enabled
    logDebug('Checking location service...');
    final serviceEnabled = await PermissionService.isLocationServiceEnabled();
    
    if (!serviceEnabled) {
      logError('❌ Location service is disabled');
      throw Exception('Location (GPS) is turned off. Turn it on in the phone settings.');
    }
    logDebug('✅ Location service is enabled');
    
    // 2. Request permissions
    logDebug('Requesting permissions...');
    final hasPermission = await PermissionService.requestAllPermissions(
        requestBackground: requestBackground);
    
    if (!hasPermission) {
      logError('❌ Failed to get required permissions');
      
      // Print detailed status for debugging
      final status = await PermissionService.getDetailedStatus();
      logDebug('📊 Detailed Status: $status');
      
      throw Exception('Location permission was not granted. Allow location access in the phone settings.');
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
  // GPS LOG (CSV) — sesi log dibuka/ditutup oleh TrackingEngine: selama ada
  // project merekam. Status tracking per project ada di TrackingSessionManager.
  // ============================================================================

  Future<void> startGpsLog() => _gpsLogger.startSession();

  Future<void> stopGpsLog() => _gpsLogger.stopSession();

  /// Teks ringkasan multi-project untuk notifikasi service background.
  void setTrackingNotificationText(String text) =>
      _backgroundTracking.setNotificationText(text);

  /// Expose GPS log file listing for export / debug screens.
  Future<List<File>> getGpsLogFiles() => _gpsLogger.listLogFiles();

  /// Delete logs older than [days] days (call on app startup for housekeeping).
  Future<void> cleanOldGpsLogs({int days = 30}) =>
      _gpsLogger.deleteOldLogs(days: days);

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

  /// Restart tracking aktif agar setelan GPS baru (pipeline & interval) langsung
  /// dipakai — foreground selalu, background hanya bila sedang berjalan.
  Future<void> restartTracking() async {
    if (_currentProvider == LocationProvider.phone) {
      await _phoneGps.stopTracking();
      await _phoneGps.startTracking();
    }
    if (_backgroundTracking.isRunning) {
      await stopBackgroundTracking();
      await startBackgroundTracking();
    }
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

          // Hanya log CSV (aktif selama ada project merekam). Titik ke sesi
          // diumpankan TrackingEngine dari stream yang sama.
          _gpsLogger.log(point);
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
  
  /// Status background service (dilaporkan isolate, tak basi — lihat
  /// [BackgroundTrackingService.decideServiceStart]).
  bool get isBackgroundServiceRunning => _backgroundTracking.isRunning;

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
    _publishEmlidStatus();
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
  
  /// Sambung ke Emlid (dipicu user). Setelah tersambung, koneksi yang putus
  /// disambung ulang otomatis sampai user menekan Disconnect.
  Future<bool> connectEmlidTCP({
    required String host,
    required int port,
    required CoordinateFormat coordinateFormat,
  }) async {
    logInfo('Connecting to Emlid at $host:$port (${coordinateFormat.name})',
        tag: 'EMLID');
    _addConsoleLog('Connecting to $host:$port...');
    // Sesi lama berhenti total: auto-reconnect baru aktif lagi bila connect
    // INI sukses. Tanpa ini, putus seketika memicu reconnect "hantu" dari
    // sesi sebelumnya walau connect dilaporkan gagal.
    _autoReconnect = false;
    _cancelReconnect();
    await _closeSocket();
    _coordinateFormat = coordinateFormat;
    _lastHost = host;
    _lastPort = port;

    final ok = await _openSocket(host, port);
    if (!ok) {
      _autoReconnect = false;
      _publishEmlidStatus();
      return false;
    }

    // Tunggu data pertama agar user langsung tahu bila format/output salah.
    _addConsoleLog('Waiting for data...');
    await Future.delayed(const Duration(seconds: 3));
    if (!_isEmlidConnected) {
      _cancelReconnect();
      _addConsoleLog('✗ Connection lost right after connecting');
      logWarn('Emlid connection lost right after connecting', tag: 'EMLID');
      _publishEmlidStatus();
      return false;
    }
    if (_bytesSinceConnect == 0) {
      _addConsoleLog('⚠ Connected, but no data yet. Check that Position '
          'Output (TCP server) is enabled on the receiver.');
    } else if (_positionsSinceConnect == 0) {
      _addConsoleLog('⚠ Receiving data but no valid position. Check that the '
          'Data Format here matches the receiver (NMEA / LLH / XYZ).');
      logWarn('Emlid: data received but no position parsed '
          '(format ${coordinateFormat.name})', tag: 'EMLID');
    } else {
      _addConsoleLog('✓ Connected, receiving positions');
    }

    _autoReconnect = true;
    await saveEmlidConnectionSettings(
      host: host,
      port: port,
      format: coordinateFormat,
    );
    return true;
  }

  /// Buka socket & pasang listener. Tak melempar — kegagalan dicatat.
  Future<bool> _openSocket(String host, int port) async {
    final gen = ++_socketGen;
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 15),
      );
      if (gen != _socketGen) {
        // Sudah diganti/diputus saat menunggu koneksi.
        socket.destroy();
        return false;
      }
      _emlidSocket = socket;
      _isEmlidConnected = true;
      _emlidBuffer = '';
      _nmeaParser = NmeaStreamParser();
      _bytesSinceConnect = 0;
      _positionsSinceConnect = 0;
      _lastEmlidBytesAt = DateTime.now();
      _reconnectAttempt = 0;
      _addConsoleLog('✓ TCP Socket connected');
      _addConsoleLog('Format: ${_coordinateFormat.name.toUpperCase()}');
      logInfo('Emlid socket connected ($host:$port)', tag: 'EMLID');

      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.listen(
        _handleEmlidData,
        onError: (Object error) {
          _addConsoleLog('✗ Socket Error: $error');
          _onSocketClosed(gen, 'socket error: $error');
        },
        onDone: () {
          _addConsoleLog('✗ Connection closed');
          _onSocketClosed(gen, 'closed by receiver/network');
        },
        cancelOnError: true,
      );

      // Perintah pemicu (beberapa firmware menunggu input sebelum mengirim).
      try {
        socket.write('\r\n');
        if (_coordinateFormat == CoordinateFormat.nmea) {
          socket.write('\$GPGGA\r\n');
        }
        await socket.flush();
      } catch (e) {
        _addConsoleLog('⚠ Init commands error: $e');
      }

      _startWatchdog();
      _publishEmlidStatus();
      return true;
    } on SocketException catch (e) {
      final errorMsg = e.message;
      _addConsoleLog('✗ SocketException: $errorMsg');
      if (errorMsg.contains('Connection refused') ||
          e.osError?.errorCode == 61 ||
          e.osError?.errorCode == 111) {
        _addConsoleLog('→ Check Emlid settings:');
        _addConsoleLog('  1. Position Output enabled');
        _addConsoleLog('  2. TCP Server mode');
        _addConsoleLog('  3. Correct port (9090)');
      } else if (errorMsg.contains('unreachable') ||
          e.osError?.errorCode == 51 ||
          e.osError?.errorCode == 101) {
        _addConsoleLog('→ Network unreachable');
        _addConsoleLog('  1. Connect to Emlid WiFi');
        _addConsoleLog('  2. Check IP: 192.168.42.1');
      }
      logWarn('Emlid connect to $host:$port failed: $errorMsg', tag: 'EMLID');
      if (gen == _socketGen) _isEmlidConnected = false;
      return false;
    } catch (e, st) {
      _addConsoleLog('✗ Error: $e');
      logError('Emlid connect to $host:$port failed',
          tag: 'EMLID', error: e, stack: st);
      if (gen == _socketGen) _isEmlidConnected = false;
      return false;
    }
  }

  void _onSocketClosed(int gen, String reason) {
    if (gen != _socketGen) return; // socket lama yang sengaja ditutup
    _isEmlidConnected = false;
    _emlidSocket = null;
    _stopWatchdog();
    logWarn('Emlid connection lost: $reason', tag: 'EMLID');
    if (_autoReconnect) _scheduleReconnect();
    _publishEmlidStatus();
  }

  /// Backoff 2 → 4 → 8 → 16 → 30 dtk, terus mencoba selama auto-reconnect aktif
  /// (mis. surveyor berjalan menjauh lalu kembali ke jangkauan Wi-Fi Emlid).
  void _scheduleReconnect() {
    final host = _lastHost, port = _lastPort;
    if (host == null || port == null) return;
    _reconnectTimer?.cancel();
    const delays = [2, 4, 8, 16, 30];
    final delay = Duration(
        seconds: delays[math.min(_reconnectAttempt, delays.length - 1)]);
    _reconnectAttempt++;
    _addConsoleLog('Reconnecting in ${delay.inSeconds}s '
        '(attempt $_reconnectAttempt)...');
    _reconnectTimer = Timer(delay, () async {
      if (!_autoReconnect || _isEmlidConnected) return;
      final ok = await _openSocket(host, port);
      if (ok) {
        logInfo('Emlid reconnected after $_reconnectAttempt attempt(s)',
            tag: 'EMLID');
      } else if (_autoReconnect) {
        _scheduleReconnect();
      }
      _publishEmlidStatus();
    });
    _publishEmlidStatus();
  }

  /// Auto-reconnect aktif (sesudah connect sukses, sampai Disconnect).
  @visibleForTesting
  bool get autoReconnectEnabled => _autoReconnect;

  /// Ada percobaan sambung ulang yang sedang menunggu.
  @visibleForTesting
  bool get isReconnectScheduled => _reconnectTimer?.isActive ?? false;

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
  }

  /// Socket "setengah mati" (tak ada data > 30 dtk tanpa onDone, sering di
  /// Wi-Fi lemah) → tutup paksa agar auto-reconnect berjalan.
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      final last = _lastEmlidBytesAt;
      if (!_isEmlidConnected || last == null) return;
      if (DateTime.now().difference(last) > const Duration(seconds: 30)) {
        _addConsoleLog('✗ No data for 30s — reconnecting');
        final gen = _socketGen;
        final socket = _emlidSocket;
        _socketGen++; // abaikan onDone socket lama
        socket?.destroy();
        _isEmlidConnected = false;
        _emlidSocket = null;
        _stopWatchdog();
        logWarn('Emlid stalled (no data for 30s, socket gen $gen)',
            tag: 'EMLID');
        if (_autoReconnect) _scheduleReconnect();
        _publishEmlidStatus();
      }
    });
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  Future<void> _closeSocket() async {
    _socketGen++; // listener socket lama tak lagi memicu reconnect
    _stopWatchdog();
    final socket = _emlidSocket;
    _emlidSocket = null;
    _isEmlidConnected = false;
    try {
      await socket?.close();
    } catch (e) {
      logDebug('Closing Emlid socket: $e', tag: 'EMLID');
      socket?.destroy();
    }
  }

  /// Putus manual oleh user: hentikan juga auto-reconnect.
  Future<void> disconnectEmlidTCP() async {
    try {
      _autoReconnect = false;
      _cancelReconnect();
      await _closeSocket();
      _emlidBuffer = '';
      _lastEmlidPoint = null;
      _lastEmlidDataTime = null;
      _belowRequirement = false;
      _lastReceivedQuality = null;
      _addConsoleLog('Disconnected');
      logInfo('Emlid disconnected by user', tag: 'EMLID');
    } catch (e, st) {
      logError('Error disconnecting Emlid', tag: 'EMLID', error: e, stack: st);
    } finally {
      _publishEmlidStatus();
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
      _lastEmlidBytesAt = DateTime.now();
      _bytesSinceConnect += data.length;
      _emlidBuffer += utf8.decode(data, allowMalformed: true);
      // Tanpa newline (mis. format biner ERB) buffer tak boleh tumbuh terus.
      if (_emlidBuffer.length > 16384) {
        _emlidBuffer = _emlidBuffer.substring(_emlidBuffer.length - 4096);
      }

      final lines = _emlidBuffer.split('\n');
      _emlidBuffer = lines.removeLast();

      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;

        _addConsoleLog('< $line');

        final GeoPoint? point;
        switch (_coordinateFormat) {
          case CoordinateFormat.nmea:
            point = _nmeaParser.parse(line);
            break;
          case CoordinateFormat.llh:
            point = parseRtklibLlh(line);
            break;
          case CoordinateFormat.xyz:
            point = parseRtklibXyz(line);
            break;
        }
        if (point == null) continue;

        _positionsSinceConnect++;
        _lastEmlidDataTime = DateTime.now();
        _lastReceivedQuality = point.fixQuality;
        if (_meetsQualityRequirement(point)) {
          _lastEmlidPoint = point; // sumber getCurrentLocation utk Emlid live
          _setBelowRequirement(false);
          _emlidLocationController.add(point);
          _gpsLogger.log(point);
        } else {
          // Tetap kirim untuk TAMPILAN (marker bergerak, ring oranye) tapi
          // ditandai tak layak rekam — dulu dibuang diam-diam sehingga marker
          // membeku dan user mengira tracking masih merekam.
          _setBelowRequirement(true);
          _emlidLocationController.add(point.copyWith(recordable: false));
        }
      }
    } catch (e, st) {
      _addConsoleLog('✗ Parse error: $e');
      logError('Emlid data handling failed', tag: 'EMLID', error: e, stack: st);
    }
  }

  void _setBelowRequirement(bool below) {
    if (below == _belowRequirement) return;
    _belowRequirement = below;
    if (below) {
      _addConsoleLog('⚠ Quality ${_lastReceivedQuality ?? '?'} below '
          'requirement "${_requiredFixQuality.name}" — positions not recorded');
      logWarn('RTK quality ${_lastReceivedQuality ?? '?'} below requirement '
          '"${_requiredFixQuality.name}" — points not recorded', tag: 'EMLID');
    } else {
      logInfo('RTK quality back to ${_lastReceivedQuality ?? '?'}',
          tag: 'EMLID');
    }
    _publishEmlidStatus();
  }

  bool _meetsQualityRequirement(GeoPoint point) =>
      point.fixQuality != null &&
      meetsFixRequirement(_requiredFixQuality, point.fixQuality);

  void _publishEmlidStatus() {
    emlidStatus.value = EmlidStatus(
      connected: _isEmlidConnected,
      reconnecting: _autoReconnect && !_isEmlidConnected,
      reconnectAttempt: _reconnectAttempt,
      lastQuality: _lastReceivedQuality,
      belowRequirement: _isEmlidConnected && _belowRequirement,
      requiredQuality: _requiredFixQuality.name,
    );
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
  
  /// Luas poligon (m²). Memakai rumus yang sama dengan alat ukur peta
  /// (proyeksi lokal dengan koreksi cos(lintang)) — dulu shoelace pada derajat
  /// × 111320² tanpa koreksi bujur, sehingga luas di info card berbeda dari
  /// alat ukur (±0,5–1 % di Indonesia, makin besar di lintang tinggi).
  double calculatePolygonArea(List<GeoPoint> points) {
    if (points.length < 3) return 0;
    return polygonAreaSqMeters(
        points.map((p) => LatLng(p.latitude, p.longitude)).toList());
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
