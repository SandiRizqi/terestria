import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service untuk mengelola FCM topic subscription berdasarkan scope user.
/// Format topic: scope_7, scope_12, dst.
class ScopeTopicService {
  static const String _subscribedScopesKey = 'fcm_subscribed_scopes';

  // Singleton
  static final ScopeTopicService _instance = ScopeTopicService._internal();
  factory ScopeTopicService() => _instance;
  ScopeTopicService._internal();

  Future<void> syncTopics(List<int> newScopes) async {
    final oldScopes = await _getSubscribedScopes();

    final oldSet = oldScopes.toSet();
    final newSet = newScopes.toSet();

    final toSubscribe = newSet.difference(oldSet).toList();
    final toUnsubscribe = oldSet.difference(newSet).toList();

    if (toSubscribe.isNotEmpty) {
      await subscribeToTopics(toSubscribe);
    }

    if (toUnsubscribe.isNotEmpty) {
      await unsubscribeFromTopics(toUnsubscribe);
    }

    // Simpan scope terbaru
    await _saveSubscribedScopes(newScopes);

    _debugPrintScopes(
      subscribed: toSubscribe,
      unsubscribed: toUnsubscribe,
      kept: newSet.intersection(oldSet).toList(),
    );
  }

  /// Subscribe ke FCM topic untuk setiap scope di [scopes].
  Future<void> subscribeToTopics(List<int> scopes) async {
    for (final scope in scopes) {
      final topic = _topicName(scope);
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        print('✅ [FCM] Subscribed to: $topic');
      } catch (e) {
        print('⚠️ [FCM] Failed to subscribe to $topic: $e');
      }
    }
  }

  /// Unsubscribe dari FCM topic untuk setiap scope di [scopes].
  Future<void> unsubscribeFromTopics(List<int> scopes) async {
    for (final scope in scopes) {
      final topic = _topicName(scope);
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        print('✅ [FCM] Unsubscribed from: $topic');
      } catch (e) {
        print('⚠️ [FCM] Failed to unsubscribe from $topic: $e');
      }
    }
  }

  /// Unsubscribe semua topic yang tersimpan di SharedPreferences.
  /// Dipanggil saat user logout.
  Future<void> unsubscribeAll() async {
    final scopes = await _getSubscribedScopes();
    if (scopes.isNotEmpty) {
      await unsubscribeFromTopics(scopes);
    }
    await _clearSubscribedScopes();
    print('✅ [FCM] All scope topics unsubscribed and cleared');
  }

  /// Kembalikan list scope yang saat ini tersimpan di SharedPreferences.
  Future<List<int>> getSubscribedScopes() => _getSubscribedScopes();

  // ─── Private Helpers ───────────────────────────────────────────────────────

  String _topicName(int scope) => 'scope_$scope';

  Future<List<int>> _getSubscribedScopes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_subscribedScopesKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => e as int).toList();
    } catch (e) {
      print('⚠️ [FCM] Failed to read subscribed scopes: $e');
      return [];
    }
  }

  Future<void> _saveSubscribedScopes(List<int> scopes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_subscribedScopesKey, jsonEncode(scopes));
    } catch (e) {
      print('⚠️ [FCM] Failed to save subscribed scopes: $e');
    }
  }

  Future<void> _clearSubscribedScopes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_subscribedScopesKey);
    } catch (e) {
      print('⚠️ [FCM] Failed to clear subscribed scopes: $e');
    }
  }

  void _debugPrintScopes({
    required List<int> subscribed,
    required List<int> unsubscribed,
    required List<int> kept,
  }) {
    print('📡 [FCM] Topic sync result:');
    if (subscribed.isNotEmpty) {
      print('   ➕ Subscribed   : ${subscribed.map(_topicName).join(', ')}');
    }
    if (unsubscribed.isNotEmpty) {
      print('   ➖ Unsubscribed : ${unsubscribed.map(_topicName).join(', ')}');
    }
    if (kept.isNotEmpty) {
      print('   ✔️  Kept         : ${kept.map(_topicName).join(', ')}');
    }
    if (subscribed.isEmpty && unsubscribed.isEmpty) {
      print('   ✔️  No changes needed');
    }
  }
}
