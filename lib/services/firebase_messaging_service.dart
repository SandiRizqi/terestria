import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';

// Background message handler - HARUS top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📱 Background message: ${message.messageId}');
  print('📱 Data: ${message.data}');
  
  if (message.notification != null) {
    print('📱 Notification: ${message.notification!.title}');
  }
}

class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  // Initialize Firebase Messaging
  Future<void> initialize() async {
    try {
      // Request permission (penting untuk iOS, opsional untuk Android)
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('🔔 Permission status: ${settings.authorizationStatus}');

      // Setup notification channel untuk Android
      await _setupNotificationChannel();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get FCM token
      _fcmToken = await _firebaseMessaging.getToken();
      print('🔑 FCM Token: $_fcmToken');

      // Listen to token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        print('🔄 Token refreshed: $newToken');
        // TODO: Kirim token baru ke server Anda
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
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
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
  void _handleForegroundMessage(RemoteMessage message) {
    print('📨 Foreground message received');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');

    // Tampilkan notification ketika app di foreground
    if (message.notification != null) {
      _showLocalNotification(message);
    }
  }

  // Handle notification tap
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('🔔 Notification tapped!');
    print('Data: ${message.data}');
    
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
      icon: '@drawable/ic_stat_notification',
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
}
