import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'fcm_token_service.dart';
import 'database_service.dart';
import 'notification_event_service.dart';
import 'notification_sync_service.dart' show stableNotificationId;
import '../models/notification_model.dart';

import '../utils/app_logger.dart';
// Background message handler - HARUS top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  logDebug('📱 Background message: ${message.messageId}', tag: 'FCM');
  logDebug('📱 Data: ${message.data}', tag: 'FCM');
  
  if (message.notification != null) {
    logDebug('📱 Notification: ${message.notification!.title}', tag: 'FCM');
    
    // Save notification to database
    try {
      final databaseService = DatabaseService();
      final data = message.data.isNotEmpty ? message.data : null;
      final notification = NotificationModel(
        // Id stabil dari object_id → cocok dgn hasil sync (anti-dobel).
        id: stableNotificationId(data) ??
            message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        data: data,
        receivedAt: DateTime.now(),
        isRead: false,
      );
      
      await databaseService.saveNotification(notification);
      logDebug('✅ Background notification saved to database', tag: 'FCM');
      
      // Notify listeners about new notification
      NotificationEventService().notifyNewNotification();
    } catch (e) {
      logError('❌ Error saving background notification: $e', tag: 'FCM');
    }
  }
}

class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FCMTokenService _fcmTokenService = FCMTokenService();
  final DatabaseService _databaseService = DatabaseService();
  final NotificationEventService _notificationEventService = NotificationEventService();
  
  String? _fcmToken;
  String? _authToken;
  
  // Callback untuk notify UI tentang notifikasi baru
  Function? onNewNotificationCallback;
  
  String? get fcmToken => _fcmToken;

  // Initialize Firebase Messaging
  Future<void> initialize({String? authToken}) async {
    _authToken = authToken;
    try {
      // Request permission (penting untuk iOS, opsional untuk Android)
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      logDebug('🔔 Permission status: ${settings.authorizationStatus}', tag: 'FCM');

      // Initialize FCM Token Service
      await _fcmTokenService.initialize();

      // Setup notification channel untuk Android
      await _setupNotificationChannel();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get FCM token
      _fcmToken = await _firebaseMessaging.getToken();
      logDebug('🔑 FCM token: ${_fcmToken == null ? 'none' : 'ada (${_fcmToken!.length} karakter)'}', tag: 'FCM');

      // Register token to backend if auth token available
      if (_fcmToken != null && _authToken != null) {
        await _registerTokenToBackend(_fcmToken!, _authToken!);
      }

      // Listen to token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        logDebug('🔄 FCM token diperbarui (${newToken.length} karakter)', tag: 'FCM');
        // Register new token to backend
        if (_authToken != null) {
          _registerTokenToBackend(newToken, _authToken!);
        }
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification tap (app in background)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Check if app was opened from terminated state
      RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      logDebug('✅ Firebase Messaging initialized successfully', tag: 'FCM');
    } catch (e) {
      logError('❌ Error initializing Firebase Messaging: $e', tag: 'FCM');
    }
  }

  // Setup notification channel untuk Android
  Future<void> _setupNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'High Importance Notifications', // title
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@drawable/ic_stat_notification');
    
    const DarwinInitializationSettings iOSSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iOSSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  // Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) async {
    logDebug('📨 Foreground message received', tag: 'FCM');
    logDebug('Title: ${message.notification?.title}', tag: 'FCM');
    logDebug('Body: ${message.notification?.body}', tag: 'FCM');
    logDebug('Data: ${message.data}', tag: 'FCM');

    // Save notification to database
    await _saveNotificationToDatabase(message);

    // Tampilkan notification ketika app di foreground
    if (message.notification != null) {
      _showLocalNotification(message);
    }
  }

  // Handle notification tap
  void _handleMessageOpenedApp(RemoteMessage message) async {
    logDebug('🔔 Notification tapped!', tag: 'FCM');
    logDebug('Data: ${message.data}', tag: 'FCM');
    
    // Save notification to database if not already saved
    await _saveNotificationToDatabase(message);
    
    // TODO: Navigate ke screen tertentu berdasarkan data
    // Contoh: 
    // if (message.data['type'] == 'new_task') {
    //   Navigator.push(context, MaterialPageRoute(builder: (_) => TaskScreen()));
    // }
  }

  // Handle notification tap (local)
  void _onNotificationTapped(NotificationResponse response) {
    logDebug('🔔 Local notification tapped!', tag: 'FCM');
    logDebug('Payload: ${response.payload}', tag: 'FCM');
    
    // TODO: Handle navigation based on payload
  }

  // Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@drawable/ic_stat_edit_location',
    );

    const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? '',
      notificationDetails,
      payload: message.data.toString(),
    );
  }

  // Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
    logDebug('📢 Subscribed to topic: $topic', tag: 'FCM');
  }

  // Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
    logDebug('🔇 Unsubscribed from topic: $topic', tag: 'FCM');
  }

  // Delete token
  Future<void> deleteToken() async {
    await _firebaseMessaging.deleteToken();
    _fcmToken = null;
    logDebug('🗑️ FCM token deleted', tag: 'FCM');
  }

  // Register token to backend
  Future<void> _registerTokenToBackend(String fcmToken, String authToken) async {
    try {
      final success = await _fcmTokenService.registerToken(fcmToken, authToken);
      if (success) {
        logDebug('✅ Token registered to backend', tag: 'FCM');
      } else {
        logWarn('⚠️ Failed to register token to backend', tag: 'FCM');
      }
    } catch (e) {
      logError('❌ Error registering token to backend: $e', tag: 'FCM');
    }
  }

  // Update auth token (call this after login)
  Future<void> updateAuthToken(String authToken) async {
    _authToken = authToken;
    
    // Register current FCM token to backend
    if (_fcmToken != null) {
      await _registerTokenToBackend(_fcmToken!, authToken);
    } else {
      // Get FCM token if not available
      _fcmToken = await _firebaseMessaging.getToken();
      if (_fcmToken != null) {
        await _registerTokenToBackend(_fcmToken!, authToken);
      }
    }
  }

  // Deactivate token on logout
  Future<void> deactivateToken(String authToken) async {
    try {
      await _fcmTokenService.deactivateToken(authToken);
      _authToken = null;
      logDebug('✅ Token deactivated from backend', tag: 'FCM');
    } catch (e) {
      logError('❌ Error deactivating token: $e', tag: 'FCM');
    }
  }

  // Deactivate all tokens (global logout)
  Future<void> deactivateAllTokens(String authToken) async {
    try {
      await _fcmTokenService.deactivateAllTokens(authToken);
      _authToken = null;
      logDebug('✅ All tokens deactivated from backend', tag: 'FCM');
    } catch (e) {
      logError('❌ Error deactivating all tokens: $e', tag: 'FCM');
    }
  }

  // Save notification to database
  Future<void> _saveNotificationToDatabase(RemoteMessage message) async {
    try {
      final data = message.data.isNotEmpty ? message.data : null;
      final notification = NotificationModel(
        id: stableNotificationId(data) ??
            message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: message.notification?.title ?? 'Notification',
        body: message.notification?.body ?? '',
        data: data,
        receivedAt: DateTime.now(),
        isRead: false,
      );

      await _databaseService.saveNotification(notification);
      logDebug('✅ Notification saved to database', tag: 'FCM');
      
      // Notify listeners about new notification
      _notificationEventService.notifyNewNotification();
      
      // Call callback if set (for immediate UI update)
      if (onNewNotificationCallback != null) {
        onNewNotificationCallback!();
      }
    } catch (e) {
      logError('❌ Error saving notification to database: $e', tag: 'FCM');
    }
  }
}
