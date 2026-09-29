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
import 'permission_service.dart';
import '../gps_settings_service.dart';
import '../settings_service.dart';
import '../gps/gps_filter_pipeline.dart';
import '../logging/log_setup.dart';
import '../../utils/app_logger.dart';

/// Keputusan saat [BackgroundTrackingService.start] dipanggil.
enum ServiceStartDecision { alreadyRunning, restartStale, freshStart }

/// Service untuk background tracking dengan proper isolate communication
@pragma('vm:entry-point')
class BackgroundTrackingService {
  /// Cache `_isRunning` bisa basi karena isolate bisa `stopSelf()` sendiri.
  /// Keputusan start mengikuti status NYATA dari plugin ([actualRunning]).
  static ServiceStartDecision decideServiceStart({
    required bool cachedRunning,
    required bool actualRunning,
  }) {
    if (actualRunning) return ServiceStartDecision.alreadyRunning;
    return cachedRunning
        ? ServiceStartDecision.restartStale
        : ServiceStartDecision.freshStart;
  }

  /// Baca flag `isRunning` dari event `service_status`; null bila event rusak.
  static bool? runningFromStatusEvent(Object? event) {
    if (event is! Map) return null;
    final v = event['isRunning'];
    return v is bool ? v : null;
  }

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

  /// Terapkan setelan "Keep screen on while tracking" saat itu juga (dipanggil
  /// dari Settings) — tak perlu menunggu tracking berikutnya.
  Future<void> applyScreenWakePreference() async {
    if (!Platform.isAndroid) return;
    try {
      final keepOn = _isRunning &&
          SettingsService().settings.keepScreenOnWhileTracking;
      if (keepOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
      logInfo('Screen wakelock ${keepOn ? 'on' : 'off'} (setting changed)',
          tag: 'SERVICE');
    } catch (e, st) {
      logError('Could not apply the screen wakelock setting',
          error: e, stack: st, tag: 'SERVICE');
    }
  }

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
            // Teruskan flag agar konsumen (screen) merekam hanya bila layak.
            recordable: event['recordable'] as bool? ?? true,
            rawLatitude: (event['rawLatitude'] as num?)?.toDouble(),
            rawLongitude: (event['rawLongitude'] as num?)?.toDouble(),
            rawAccuracy: (event['rawAccuracy'] as num?)?.toDouble(),
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
    // Isolate melapor `isRunning:false` sebelum stopSelf() (heartbeat timeout,
    // lokasi mati, error) → cache ikut mati, Start berikutnya menyalakan ulang.
    _statusSubscription = _service.on('service_status').listen((event) {
      final running = runningFromStatusEvent(event);
      if (running == null) return;
      final wasRunning = _isRunning;
      _isRunning = running;
      if (wasRunning && !running) {
        logWarn('Background service berhenti sendiri (dilaporkan isolate; '
            'alasan di bg-*.log)', tag: 'SERVICE');
        if (Platform.isAndroid) WakelockPlus.disable();
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
    
    final cached = _isRunning;
    switch (decideServiceStart(
        cachedRunning: cached, actualRunning: await _queryActualRunning())) {
      case ServiceStartDecision.alreadyRunning:
        logDebug('✅ Background service already running');
        _isRunning = true;
        // Cache mati tapi service masih hidup (mis. dari sesi app sebelumnya)
        // → listener belum terpasang di proses ini.
        if (!cached) _setupListeners();
        return true;
      case ServiceStartDecision.restartStale:
        logError('⚠️ Status "running" basi — service sudah mati, start ulang');
        _isRunning = false;
      case ServiceStartDecision.freshStart:
        break;
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

      // Escalate ke "Always" HANYA di iOS. Di Android, background tracking
      // ditanggung oleh foreground-service (foregroundServiceType=location +
      // notifikasi persisten) yang jalan dengan When-In-Use — meminta Always di
      // sini malah memicu redirect ke Settings di Android 11+. Request Always
      // Android (opsional, best-effort) sudah dilakukan di _requestAndroidPermissions.
      if (Platform.isIOS && permission == LocationPermission.whileInUse) {
        permission = await PermissionService.ensureBackgroundPermission();
      }

      // Di iOS, tanpa "Always" CLLocationManager berhenti mengirim lokasi
      // begitu app keluar dari foreground → track background akan terputus.
      // Tetap lanjut (bagian foreground tetap jalan) tapi beri peringatan jelas.
      if (PermissionService.backgroundNeedsAlways(
          isIOS: Platform.isIOS, permission: permission)) {
        logError('⚠️ Background tracking iOS butuh izin "Always"; saat ini '
            '$permission. Track bisa berhenti saat app di background — minta '
            'user set "Always/Selalu" di Pengaturan.');
      }

      logDebug('✅ Location permission verified: $permission');

      // Layar tetap menyala hanya bila user memilihnya di Settings. Service
      // lokasi (foreground service) tetap merekam dengan layar mati; dulu
      // layar selalu dipaksa menyala dan menguras baterai di lapangan.
      if (Platform.isAndroid &&
          SettingsService().settings.keepScreenOnWhileTracking) {
        await WakelockPlus.enable();
        logDebug('🔋 Screen wakelock enabled (setting)');
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
  
  /// Teks notifikasi ringkasan multi-project (dari TrackingEngine). Isolate
  /// memakainya sebagai judul status, menggantikan teks default.
  void setNotificationText(String text) {
    if (!_isRunning) return;
    try {
      _service.invoke('set_notification_text', {'text': text});
    } catch (e) {
      logError('❌ Error sending notification text: $e');
    }
  }

  /// Teruskan status Mode Diagnostik ke isolate (null = mati).
  void setDiagnosticUntil(DateTime? until) {
    if (!_isRunning) return;
    try {
      _service.invoke(
          'set_diagnostic', {'until': until?.millisecondsSinceEpoch});
    } catch (e) {
      logError('❌ Error sending diagnostic mode: $e');
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
  
  /// Status nyata dari plugin; fallback ke cache bila query gagal.
  Future<bool> _queryActualRunning() async {
    try {
      return await _service.isRunning();
    } catch (e) {
      logError('⚠️ Gagal query status service: $e');
      return _isRunning;
    }
  }

  /// Stop background tracking
  Future<void> stop() async {
    if (!_isRunning && !await _queryActualRunning()) {
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
  
  /// Laporkan ke app bahwa service berhenti SEBELUM stopSelf(), agar cache
  /// `_isRunning` di app tidak basi (Start berikutnya menyalakan ulang).
  static Future<void> _reportStoppedAndStop(
    ServiceInstance service, {
    required String reason,
    bool expected = false,
  }) async {
    // Alasan berhenti = informasi terpenting saat men-debug "titik tak
    // terekam" → selalu tercatat di bg-*.log.
    if (expected) {
      logInfo('Service berhenti: $reason', tag: 'SERVICE');
    } else {
      logWarn('Service berhenti sendiri: $reason', tag: 'SERVICE');
    }
    service.invoke('service_status', {'isRunning': false});
    await AppLogger.flush(); // log isolate jangan hilang saat isolate mati
    service.stopSelf();
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
    // Isolate ini punya berkas log sendiri (bg-*.log) — digabung saat ekspor.
    await initAppLogging(source: 'bg');
    service.on('set_diagnostic').listen((event) {
      final ms = event?['until'];
      AppLogger.setDiagnosticUntil(
          ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null);
    });
    
    bool isPaused = false;
    int locationCount = 0;
    // Snapshot setelan GPS dibaca dari SharedPreferences (isolate tak berbagi
    // singleton foreground). Perubahan berlaku setelah tracking di-restart.
    final gpsSettings = await GpsSettingsService.loadFromPrefs();
    // Pipeline pengolahan bersama dengan foreground (akurasi/speed/static-noise/
    // EMA/round) — memastikan track background diolah identik dengan foreground.
    final pipeline = GpsFilterPipeline(gpsSettings.toFilterConfig());
    StreamSubscription<Position>? subscription;
    Timer? heartbeatTimer;
    DateTime lastHeartbeat = DateTime.now();
    String notificationLabel = 'Location tracking active';
    
    try {
      logDebug('📍 Setting up Geolocator for background tracking...');
      
      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logError('❌ Location service not enabled');
        _reportStoppedAndStop(service, reason: 'phone location (GPS) service turned off');
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
        _reportStoppedAndStop(service, reason: 'stop requested by the app', expected: true);
      });
      
      // Ringkasan multi-project dari app ("Merekam 2 project · 1 jeda").
      service.on('set_notification_text').listen((event) async {
        final text = event?['text'];
        if (text is! String || text == notificationLabel) return;
        notificationLabel = text;
        await NotificationService.updateNotification(
            'Terestria Tracking', notificationLabel);
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
          _reportStoppedAndStop(service, reason: 'no heartbeat for > 15 s (app closed or frozen)');
        } else {
          logDebug('💚 Service alive - last heartbeat ${timeSinceLastHeartbeat.inSeconds}s ago');
        }
      });
      
      logDebug('✅ Command listeners setup');
      logDebug('🚀 Starting Geolocator location stream...');
      
      // Background location settings dengan distanceFilter untuk hemat baterai
      // dan kurangi noise — dari snapshot setelan user (konsisten foreground).
      final distanceFilterM = gpsSettings.distanceFilterMeters.toInt();
      final locationSettings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: distanceFilterM,
              intervalDuration:
                  Duration(milliseconds: gpsSettings.trackingIntervalMs),
              forceLocationManager: false,
            )
          : Platform.isIOS
              ? AppleSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: distanceFilterM,
                  activityType: ActivityType.other,
                  pauseLocationUpdatesAutomatically: false,
                  // WAJIB agar iOS terus mengirim lokasi saat app di background
                  // (bersama UIBackgroundModes 'location' + izin Always).
                  allowBackgroundLocationUpdates: true,
                  showBackgroundLocationIndicator: true, // indicator biru di iOS
                )
              : LocationSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
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

          // ✅ CRITICAL: Send location to UI via service communication.
          // Marker SELALU dikirim (display); `recordable` menandai apakah UI
          // boleh merekamnya ke jalur — identik dengan foreground.
          final locationMap = {
            'latitude': lat,
            'longitude': lon,
            'altitude': position.altitude,
            'accuracy': processed.accuracy,
            'speed': speedKmh,
            'timestamp': position.timestamp.millisecondsSinceEpoch,
            'recordable': processed.recordable,
            // Koordinat mentah untuk titik jalur (lihat GeoPoint.forRecording).
            if (processed.rawLatitude != null)
              'rawLatitude': processed.rawLatitude,
            if (processed.rawLongitude != null)
              'rawLongitude': processed.rawLongitude,
            if (processed.rawAccuracy != null)
              'rawAccuracy': processed.rawAccuracy,
          };

          logDebug('📤 SENDING TO FOREGROUND: $locationMap');

          service.invoke('location_update', locationMap);
          logDebug('✅ Data sent via service.invoke()');

          // Persist untuk recovery — HANYA titik yang layak direkam (jalur
          // tak boleh terisi display-only/outlier/drift diam).
          if (processed.recordable) {
            await _saveLocationToPrefs(
              lat,
              lon,
              position.altitude,
              processed.accuracy,
              speedKmh,
            );
          }
          
          // Update notification setiap 5 detik untuk monitoring
          if (locationCount % 5 == 0) {
            final accuracy = position.accuracy.toStringAsFixed(1);
            // Ringkasan project dari app + akurasi terkini (bukan jumlah fix
            // mentah, yang tak sama dengan titik per project).
            await NotificationService.updateNotification(
              'Terestria Tracking',
              '$notificationLabel · ±${accuracy} m',
            );
          }
          
          // Send status
          service.invoke('service_status', {'isRunning': true});
        },
        onError: (error) {
          logError('Stream lokasi background error',
              tag: 'SERVICE', error: error);
        },
      );

      logInfo(
          'Service background mulai (${Platform.operatingSystem}, '
          'distanceFilter=${distanceFilterM} m, '
          'interval=${gpsSettings.trackingIntervalMs} ms)',
          tag: 'SERVICE');

    } catch (e, stack) {
      logError('Error di service background',
          tag: 'SERVICE', error: e, stack: stack);
      _reportStoppedAndStop(service, reason: 'error: $e');
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
