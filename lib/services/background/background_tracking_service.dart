import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/geo_data_model.dart';
import 'notification_service.dart';
import '../../config/location_config.dart';
import '../gps/gps_filter_pipeline.dart';
import '../../utils/app_logger.dart';

/// Service untuk background tracking dengan proper isolate communication
@pragma('vm:entry-point')
class BackgroundTrackingService {
  static final BackgroundTrackingService _instance = BackgroundTrackingService._internal();
  factory BackgroundTrackingService() => _instance;
  BackgroundTrackingService._internal();
  
  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _isInitialized = false;
  bool _isRunning = false;
  
  // Stream controller untuk menerima location dari background
  final StreamController<GeoPoint> _locationStreamController = 
      StreamController<GeoPoint>.broadcast();
  
  StreamSubscription? _locationUpdateSubscription;
  StreamSubscription? _statusSubscription;
  
  // ✅ NEW: Timer untuk retry listener setup
  Timer? _listenerRetryTimer;
  int _listenerRetryCount = 0;
  static const int _maxRetries = 5;
  
  Stream<GeoPoint> get locationStream => _locationStreamController.stream;
  
  bool get isRunning => _isRunning;
  
  /// Initialize background service
  Future<void> initialize() async {
    if (_isInitialized) {
      logDebug('⚠️ Background service already initialized');
      return;
    }
    
    logDebug('🚀 Initializing background service...');
    
    try {
      // 1. Initialize notification FIRST (CRITICAL untuk Android)
      await NotificationService.initialize();
      
      // 2. Configure background service
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: NotificationService.channelId,
          initialNotificationTitle: 'Terestria',
          initialNotificationContent: 'Initializing...',
          foregroundServiceNotificationId: NotificationService.notificationId,
          foregroundServiceTypes: [AndroidForegroundType.location],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onStart,
          onBackground: _onIosBackground,
        ),
      );
      
      _isInitialized = true;
      logDebug('✅ Background service initialized');
      
    } catch (e) {
      logError('❌ Failed to initialize background service: $e');
      rethrow;
    }
  }
  
  // ✅ FIXED: Setup listeners dengan retry mechanism
  void _setupListeners() {
    logDebug('═══════════════════════════════════════');
    logDebug('📡 Setting up background service listeners...');
    logDebug('═══════════════════════════════════════');
    
    // Cancel existing subscriptions dan retry timer
    _locationUpdateSubscription?.cancel();
    _statusSubscription?.cancel();
    _listenerRetryTimer?.cancel();
    _listenerRetryCount = 0;
    
    // Setup listener untuk data dari background
    _locationUpdateSubscription = _service.on('location_update').listen((event) {
      logDebug('🔔 LISTENER TRIGGERED! Event received: ${event != null}');
      
      // ✅ Reset retry count karena listener berhasil terima data
      _listenerRetryCount = 0;
      _listenerRetryTimer?.cancel();
      
      try {
        if (event != null && event is Map) {
          final point = GeoPoint(
            latitude: (event['latitude'] as num).toDouble(),
            longitude: (event['longitude'] as num).toDouble(),
            altitude: event['altitude'] != null ? (event['altitude'] as num).toDouble() : null,
            accuracy: event['accuracy'] != null ? (event['accuracy'] as num).toDouble() : null,
            speed: event['speed'] != null ? (event['speed'] as num).toDouble() : null,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              event['timestamp'] as int,
            ),
          );
          
          logDebug('📥 RECEIVED FROM BACKGROUND:');
          logDebug('   Raw event: $event');
          logDebug('   Lat: ${point.latitude}');
          logDebug('   Lon: ${point.longitude}');
          logDebug('   Time: ${point.timestamp}');
          
          _locationStreamController.add(point);
          
          logDebug('✅ Added to stream controller');
        }
      } catch (e) {
        logError('❌ Error parsing location update: $e');
      }
    });
    
    // Setup status listener
    _statusSubscription = _service.on('service_status').listen((event) {
      if (event != null && event is Map) {
        _isRunning = event['isRunning'] as bool? ?? false;
        logDebug('📊 Service status: ${_isRunning ? "Running" : "Stopped"}');
      }
    });
    
    logDebug('✅ Listeners setup complete');
    
    // ✅ NEW: Start verification timer - cek apakah listener benar-benar terkoneksi
    _startListenerVerification();
  }
  
  // ✅ NEW: Verify listener connection dengan retry
  void _startListenerVerification() {
    logDebug('🔍 Starting listener verification...');
    
    _listenerRetryTimer?.cancel();
    
    // Kirim test command ke background untuk verify connection
    _service.invoke('ping_test');
    
    // Wait 3 detik, jika tidak ada response → retry setup
    _listenerRetryTimer = Timer(const Duration(seconds: 3), () {
      if (_listenerRetryCount < _maxRetries) {
        _listenerRetryCount++;
        logDebug('⚠️ Listener not responding, retry #$_listenerRetryCount/$_maxRetries');
        
        // Retry setup dengan delay lebih lama
        final retryDelay = Duration(milliseconds: 1000 * _listenerRetryCount);
        logDebug('⏳ Retry in ${retryDelay.inMilliseconds}ms...');
        
        Future.delayed(retryDelay, () {
          if (_isRunning) {
            _setupListeners();
          }
        });
      } else {
        logError('❌ Listener setup failed after $_maxRetries retries');
        logDebug('⚠️ Background tracking may not work properly');
      }
    });
  }
  
  /// Start background tracking
  Future<bool> start() async {
    logDebug('▶️ START BACKGROUND TRACKING CALLED');
    
    if (!_isInitialized) {
      logDebug('🔧 Service not initialized, initializing...');
      await initialize();
    }
    
    if (_isRunning) {
      logDebug('⚠️ Background service already running');
      return true;
    }
    
    try {
      // Verifikasi permission di foreground sebelum start background service
      logDebug('🔑 Verifying location permission in foreground...');

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logError('❌ Location service not enabled');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        logError('❌ Location permission not granted: $permission');
        return false;
      }

      logDebug('✅ Location permission verified: $permission');

      // Enable wakelock untuk menjaga tracking aktif
      if (Platform.isAndroid) {
        await WakelockPlus.enable();
        logDebug('🔋 WakeLock enabled');
      }

      // iOS: background tracking ditangani oleh flutter_background_service.
      // Tidak perlu enableBackgroundMode() — AppleSettings di isolate sudah
      // mengonfigurasi CLLocationManager untuk background.
      
      // Start service
      logDebug('🚀 Starting background service...');
      final started = await _service.startService();
      
      if (started) {
        _isRunning = true;
        await NotificationService.updateNotification(
          'Terestria Tracking',
          'Location tracking active',
        );
        
        logDebug('✅ Background service started successfully');
        logDebug('📊 Service is running: $_isRunning');
        
        // ✅ CRITICAL FIX: Tunggu lebih lama untuk Android
        // Android butuh waktu lebih lama untuk fully initialize isolate
        final initDelay = Platform.isAndroid 
            ? const Duration(milliseconds: 1500)  // Android: 1.5s
            : const Duration(milliseconds: 800);   // iOS: 0.8s
        
        logDebug('⏳ Waiting ${initDelay.inMilliseconds}ms for isolate initialization...');
        await Future.delayed(initDelay);
        
        _setupListeners();
        logDebug('✅ Listeners setup complete after service start');
        
        return true;
      } else {
        logError('❌ Failed to start background service');
        return false;
      }
      
    } catch (e) {
      logError('❌ Error starting background service: $e');
      logDebug('═══════════════════════════════════════');
      return false;
    }
  }
  
  /// Send heartbeat to background service
  void sendHeartbeat() {
    if (!_isRunning) return;
    
    try {
      _service.invoke('heartbeat');
    } catch (e) {
      logError('❌ Error sending heartbeat: $e');
    }
  }
  
  /// Stop background tracking
  Future<void> stop() async {
    if (!_isRunning) {
      logDebug('⚠️ Background service not running');
      return;
    }
    
    logDebug('⏹️ Stopping background service...');
    
    try {
      _service.invoke('stop_service');
      
      // Disable wakelock
      if (Platform.isAndroid) {
        await WakelockPlus.disable();
        logDebug('🔋 WakeLock disabled');
      }
      // iOS: tidak ada enableBackgroundMode yang perlu dimatikan,
      // flutter_background_service akan stop sendiri saat service.stopSelf() dipanggil.
      
      await NotificationService.cancelNotification();
      
      // Cancel listeners dan retry timer
      _locationUpdateSubscription?.cancel();
      _statusSubscription?.cancel();
      _listenerRetryTimer?.cancel();
      
      _isRunning = false;
      logDebug('✅ Background service stopped');
      
    } catch (e) {
      logError('❌ Error stopping background service: $e');
    }
  }
  
  /// Pause tracking
  Future<void> pause() async {
    if (!_isRunning) return;
    
    logDebug('⏸️ Pausing tracking...');
    _service.invoke('pause_tracking');
    
    await NotificationService.updateNotification(
      'Terestria Tracking',
      'Tracking paused',
    );
  }
  
  /// Resume tracking
  Future<void> resume() async {
    if (!_isRunning) return;
    
    logDebug('▶️ Resuming tracking...');
    _service.invoke('resume_tracking');
    
    await NotificationService.updateNotification(
      'Terestria Tracking',
      'Location tracking active',
    );
  }
  
  /// Background service entry point
  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    // Initialize Flutter bindings FIRST for plugin access
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    
    logDebug('═══════════════════════════════════════');
    logDebug('BACKGROUND SERVICE STARTED IN ISOLATE');
    logDebug('═══════════════════════════════════════');
    
    // Add delay to ensure plugins fully initialized
    await Future.delayed(const Duration(milliseconds: 500));
    logDebug('✅ Flutter bindings initialized');
    
    bool isPaused = false;
    int locationCount = 0;
    // Pipeline pengolahan bersama dengan foreground (akurasi/speed/static-noise/
    // EMA/round) — memastikan track background diolah identik dengan foreground.
    final pipeline = GpsFilterPipeline(GpsFilterConfig.fromDefaults());
    StreamSubscription<Position>? subscription;
    Timer? heartbeatTimer;
    DateTime lastHeartbeat = DateTime.now();
    
    try {
      logDebug('📍 Setting up Geolocator for background tracking...');
      
      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logError('❌ Location service not enabled');
        service.stopSelf();
        return;
      }
      
      logDebug('✅ Location service enabled');
      logDebug('✅ Permission assumed granted (verified in foreground)');
      logDebug('✅ Location settings configured');
      
      // ✅ NEW: Listen for ping test command
      service.on('ping_test').listen((event) {
        logDebug('Received from foreground');
        // Send immediate location update as pong response
        if (locationCount > 0) {
          logDebug('Sending location update');
        }
      });
      
      // Listen for commands
      service.on('stop_service').listen((event) async {
        logDebug('⏹️ Stop command received in background');
        heartbeatTimer?.cancel();
        await subscription?.cancel();
        await NotificationService.cancelNotification();
        service.stopSelf();
      });
      
      service.on('pause_tracking').listen((event) {
        logDebug('⏸️ Pause command received in background');
        isPaused = true;
      });
      
      service.on('resume_tracking').listen((event) {
        logDebug('▶️ Resume command received in background');
        isPaused = false;
      });
      
      // Listen for heartbeat from foreground
      service.on('heartbeat').listen((event) {
        lastHeartbeat = DateTime.now();
        logDebug('💓 Heartbeat received from foreground');
      });
      
      // Start heartbeat checker - auto-stop if no heartbeat for 15 seconds
      heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        final timeSinceLastHeartbeat = DateTime.now().difference(lastHeartbeat);
        
        if (timeSinceLastHeartbeat.inSeconds > 15) {
          logError('❌ No heartbeat for ${timeSinceLastHeartbeat.inSeconds}s - app likely closed');
          logDebug('⏹️ Auto-stopping background service...');
          
          timer.cancel();
          await subscription?.cancel();
          await NotificationService.cancelNotification();
          service.stopSelf();
        } else {
          logDebug('💚 Service alive - last heartbeat ${timeSinceLastHeartbeat.inSeconds}s ago');
        }
      });
      
      logDebug('✅ Command listeners setup');
      logDebug('🚀 Starting Geolocator location stream...');
      
      // Background location settings dengan distanceFilter untuk hemat baterai
      // dan kurangi noise — konsisten dengan PhoneGpsService (LocationConfig).
      final distanceFilterM = LocationConfig.distanceFilterMeters.toInt();
      final locationSettings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: distanceFilterM,
              intervalDuration:
                  const Duration(milliseconds: LocationConfig.trackingIntervalMs),
              forceLocationManager: false,
            )
          : Platform.isIOS
              ? AppleSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: distanceFilterM,
                  activityType: ActivityType.other,
                  pauseLocationUpdatesAutomatically: false,
                  showBackgroundLocationIndicator: true, // tunjukkan indicator background di iOS
                )
              : LocationSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: distanceFilterM,
                );

      subscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (position) async {
          if (isPaused) {
            logDebug('⏸️ Tracking paused, skipping location');
            return;
          }

          // Olah lewat pipeline bersama (akurasi/speed/static-noise/EMA/round).
          final processed = pipeline.process(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            speed: position.speed,
            timestamp: position.timestamp,
            altitude: position.altitude,
          );
          if (processed == null) {
            logDebug('⚠️ BG: Skip — dibuang filter '
                '(±${position.accuracy.toStringAsFixed(1)}m)');
            return;
          }

          locationCount++;

          logDebug('📍 BG #$locationCount '
              '${processed.latitude},${processed.longitude} '
              '±${position.accuracy.toStringAsFixed(1)}m paused=$isPaused');

          final lat = processed.latitude;
          final lon = processed.longitude;
          final speedKmh = processed.speed;

          // ✅ CRITICAL: Send location to UI via service communication
          final locationMap = {
            'latitude': lat,
            'longitude': lon,
            'altitude': position.altitude,
            'accuracy': position.accuracy,
            'speed': speedKmh,
            'timestamp': position.timestamp.millisecondsSinceEpoch,
          };
          
          logDebug('📤 SENDING TO FOREGROUND: $locationMap');
          
          service.invoke('location_update', locationMap);
          logDebug('✅ Data sent via service.invoke()');
          
          // Save to SharedPreferences untuk persistence
          await _saveLocationToPrefs(
            lat,
            lon,
            position.altitude,
            position.accuracy,
            speedKmh,
          );
          
          // Update notification setiap 5 detik untuk monitoring
          if (locationCount % 5 == 0) {
            final accuracy = position.accuracy.toStringAsFixed(1);
            await NotificationService.updateNotification(
              'Terestria Tracking',
              'Accuracy: ${accuracy}m | Points: $locationCount',
            );
          }
          
          // Send status
          service.invoke('service_status', {'isRunning': true});
        },
        onError: (error) {
          logError('❌ Location stream error in background: $error');
        },
      );
      
      logDebug('✅ Location tracking started in background isolate');
      logDebug('═══════════════════════════════════════');
      
    } catch (e) {
      logError('❌ Error in background service: $e');
      service.stopSelf();
    }
  }
  
  /// iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    logDebug('📱 iOS background handler called');
    return true;
  }
  
  /// Save location to SharedPreferences (untuk persistence)
  static Future<void> _saveLocationToPrefs(
    double lat,
    double lon,
    double? alt,
    double? acc,
    double? speed,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_lat', lat);
      await prefs.setDouble('last_lon', lon);
      if (alt != null) await prefs.setDouble('last_alt', alt);
      if (acc != null) await prefs.setDouble('last_acc', acc);
      if (speed != null) await prefs.setDouble('last_speed', speed);
      await prefs.setInt('last_time', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      logError('❌ Error saving location to prefs: $e');
    }
  }

  /// Get last saved location from SharedPreferences
  Future<GeoPoint?> getLastSavedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('last_lat');
      final lon = prefs.getDouble('last_lon');

      if (lat == null || lon == null) return null;

      return GeoPoint(
        latitude: lat,
        longitude: lon,
        altitude: prefs.getDouble('last_alt'),
        accuracy: prefs.getDouble('last_acc'),
        speed: prefs.getDouble('last_speed'),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          prefs.getInt('last_time') ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      logError('❌ Error loading last location: $e');
      return null;
    }
  }
  
  /// Dispose resources
  void dispose() {
    _locationUpdateSubscription?.cancel();
    _statusSubscription?.cancel();
    _listenerRetryTimer?.cancel();
    _locationStreamController.close();
  }
}
