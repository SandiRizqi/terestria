import 'package:shared_preferences/shared_preferences.dart';
import '../config/notification_topics.dart';
import 'firebase_messaging_service.dart';

/// Service untuk mengelola subscription notification topics
/// Menyimpan status subscribe/unsubscribe di SharedPreferences
/// dan melakukan subscribe/unsubscribe di Firebase Messaging
class NotificationTopicService {
  static final NotificationTopicService _instance = NotificationTopicService._internal();
  factory NotificationTopicService() => _instance;
  NotificationTopicService._internal();

  static const String _prefsKeyPrefix = 'notification_topic_';
  static const String _prefsInitializedKey = 'notification_topics_initialized';

  final FirebaseMessagingService _messagingService = FirebaseMessagingService();
  
  // Cache status subscribe di memory
  final Map<String, bool> _subscriptionStatus = {};

  /// Initialize - load status dari SharedPreferences
  /// Jika pertama kali, subscribe ke topic yang isDefault = true
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isInitialized = prefs.getBool(_prefsInitializedKey) ?? false;

    if (!isInitialized) {
      // Pertama kali: subscribe ke semua topic yang isDefault = true
      for (final topic in defaultNotificationTopics) {
        if (topic.isDefault) {
          await _messagingService.subscribeToTopic(topic.id);
          await prefs.setBool('$_prefsKeyPrefix${topic.id}', true);
          _subscriptionStatus[topic.id] = true;
        } else {
          await prefs.setBool('$_prefsKeyPrefix${topic.id}', false);
          _subscriptionStatus[topic.id] = false;
        }
      }
      await prefs.setBool(_prefsInitializedKey, true);
    } else {
      // Load status dari prefs
      for (final topic in defaultNotificationTopics) {
        final isSubscribed = prefs.getBool('$_prefsKeyPrefix${topic.id}') ?? topic.isDefault;
        _subscriptionStatus[topic.id] = isSubscribed;
      }
    }
  }

  /// Cek apakah user subscribe ke topic tertentu
  bool isSubscribed(String topicId) {
    return _subscriptionStatus[topicId] ?? false;
  }

  /// Subscribe ke topic
  Future<void> subscribe(String topicId) async {
    try {
      await _messagingService.subscribeToTopic(topicId);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefsKeyPrefix$topicId', true);
      
      _subscriptionStatus[topicId] = true;
    } catch (e) {
      rethrow;
    }
  }

  /// Unsubscribe dari topic
  Future<void> unsubscribe(String topicId) async {
    try {
      await _messagingService.unsubscribeFromTopic(topicId);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefsKeyPrefix$topicId', false);
      
      _subscriptionStatus[topicId] = false;
    } catch (e) {
      rethrow;
    }
  }

  /// Toggle subscribe/unsubscribe
  Future<void> toggle(String topicId) async {
    if (isSubscribed(topicId)) {
      await unsubscribe(topicId);
    } else {
      await subscribe(topicId);
    }
  }

  /// Ambil semua topicId yang aktif
  List<String> getSubscribedTopicIds() {
    return _subscriptionStatus.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }
}
