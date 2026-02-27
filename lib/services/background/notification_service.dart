import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service untuk mengelola notifikasi Android
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  static const String channelId = 'geoform_tracking';
  static const String channelName = 'Location Tracking';
  static const String channelDescription = 'Shows when tracking location';
  static const int notificationId = 888;
  
  /// Inisialisasi notification channel (HARUS dipanggil SEBELUM service start)
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    
    print('📱 Initializing notification service...');
    
    // Create notification channel untuk Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.low, // Low importance agar tidak mengganggu
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );
    
    // Register channel
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    
    // Initialize plugin
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@drawable/ic_stat_edit_location');
    
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );
    
    await _notifications.initialize(initSettings);
    
    print('✅ Notification service initialized');
  }
  
  /// Update notifikasi yang sedang aktif
  static Future<void> updateNotification(String title, String content) async {
    if (!Platform.isAndroid) return;
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      showWhen: true,
      icon: '@drawable/ic_stat_edit_location'
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );
    
    await _notifications.show(
      notificationId, 
      title, 
      content, 
      notificationDetails,
    );
  }
  
  /// Batalkan notifikasi
  static Future<void> cancelNotification() async {
    if (!Platform.isAndroid) return;
    await _notifications.cancel(notificationId);
  }
  
  /// Batalkan semua notifikasi
  static Future<void> cancelAllNotifications() async {
    if (!Platform.isAndroid) return;
    await _notifications.cancelAll();
  }
}
