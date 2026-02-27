import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'fcm_token_service.dart';
import 'database_service.dart';
import 'notification_event_service.dart';
import '../models/notification_model.dart';

// Background message handler - HARUS top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📱 Background message: ${message.messageId}');
  print('📱 Data: ${message.data}');
  
  if (message.notification != null) {
    print('📱 Notification: ${message.notification!.title}');
    
    // Save notification to database
    try {
      final databaseService = DatabaseService();
      final notification = NotificationModel(
        id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        data: message.data.isNotEmpty ? message.data : null,
        receivedAt: DateTime.now(),
        isRead: false,
      );
      
      await databaseService.saveNotification(notification);
      print('✅ Background notification saved to database');
      
      // Notify listeners about new notification
      NotificationEventService().notifyNewNotification();
    } catch (e) {
      print('❌ Error saving background notification: $e');
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

      print('🔔 Permission status: ${settings.authorizationStatus}');

      // Initialize FCM Token Service
      await _fcmTokenService.initialize();

      // Setup notification channel untuk Android
      await _setupNotificationChannel();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get FCM token
      _fcmToken = await _firebaseMessaging.getToken();
      print('🔑 FCM Token: $_fcmToken');

      // Register token to backend if auth token available
      if (_fcmToken != null && _authToken != null) {
        await _registerTokenToBackend(_fcmToken!, _authToken!);
      }

      // Listen to token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        print('🔄 Token refreshed: $newToken');
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

      print('✅ Firebase Messaging initialized successfully');
    } catch (e) {
      print('❌ Error initializing Firebase Messaging: $e');
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
    print('📨 Foreground message received');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');

    // Save notification to database
    await _saveNotificationToDatabase(message);

    // Tampilkan notification ketika app di foreground
    if (message.notification != null) {
      _showLocalNotification(message);
    }
  }

  // Handle notification tap
  void _handleMessageOpenedApp(RemoteMessage message) async {
    print('🔔 Notification tapped!');
    print('Data: ${message.data}');
    
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
    print('🔔 Local notification tapped!');
    print('Payload: ${response.payload}');
    
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
    print('📢 Subscribed to topic: $topic');
  }

  // Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
    print('🔇 Unsubscribed from topic: $topic');
  }

  // Delete token
  Future<void> deleteToken() async {
    await _firebaseMessaging.deleteToken();
    _fcmToken = null;
    print('🗑️ FCM token deleted');
  }

  // Register token to backend
  Future<void> _registerTokenToBackend(String fcmToken, String authToken) async {
    try {
      final success = await _fcmTokenService.registerToken(fcmToken, authToken);
      if (success) {
        print('✅ Token registered to backend');
      } else {
        print('⚠️ Failed to register token to backend');
      }
    } catch (e) {
      print('❌ Error registering token to backend: $e');
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
      print('✅ Token deactivated from backend');
    } catch (e) {
      print('❌ Error deactivating token: $e');
    }
  }

  // Deactivate all tokens (global logout)
  Future<void> deactivateAllTokens(String authToken) async {
    try {
      await _fcmTokenService.deactivateAllTokens(authToken);
      _authToken = null;
      print('✅ All tokens deactivated from backend');
    } catch (e) {
      print('❌ Error deactivating all tokens: $e');
    }
  }

  // Save notification to database
  Future<void> _saveNotificationToDatabase(RemoteMessage message) async {
    try {
      final notification = NotificationModel(
        id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: message.notification?.title ?? 'Notification',
        body: message.notification?.body ?? '',
        data: message.data.isNotEmpty ? message.data : null,
        receivedAt: DateTime.now(),
        isRead: false,
      );

      await _databaseService.saveNotification(notification);
      print('✅ Notification saved to database');
      
      // Notify listeners about new notification
      _notificationEventService.notifyNewNotification();
      
      // Call callback if set (for immediate UI update)
      if (onNewNotificationCallback != null) {
        onNewNotificationCallback!();
      }
    } catch (e) {
      print('❌ Error saving notification to database: $e');
    }
  }
}
