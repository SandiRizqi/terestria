import 'package:flutter/material.dart';
import '../../config/notification_topics.dart';
import '../../services/notification_topic_service.dart';
import '../../theme/app_theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final NotificationTopicService _topicService = NotificationTopicService();
  bool _isLoading = true;
  // Track topic yang sedang dalam proses toggle (untuk loading indicator per item)
  final Set<String> _togglingTopics = {};

  @override
  void initState() {
    super.initState();
    _initializeTopics();
  }

  Future<void> _initializeTopics() async {
    try {
      await _topicService.initialize();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleTopic(NotificationTopic topic, bool value) async {
    setState(() {
      _togglingTopics.add(topic.id);
    });

    try {
      if (value) {
        await _topicService.subscribe(topic.id);
      } else {
        await _topicService.unsubscribe(topic.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengubah notifikasi "${topic.label}": $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _togglingTopics.remove(topic.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryGreen,
        elevation: 0,
        title: const Text(
          'Notification Settings',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    'Pilih jenis notifikasi yang ingin Anda terima',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                // Topic list
                ...defaultNotificationTopics.map((topic) {
                  final isSubscribed = _topicService.isSubscribed(topic.id);
                  final isToggling = _togglingTopics.contains(topic.id);

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: isSubscribed
                        ? AppTheme.getCardDecoration
                        : BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      secondary: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSubscribed
                              ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                        ),
                        child: isToggling
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                topic.icon,
                                color: isSubscribed
                                    ? AppTheme.primaryGreen
                                    : Colors.grey[600],
                                size: 24,
                              ),
                      ),
                      title: Text(
                        topic.label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        topic.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      value: isSubscribed,
                      activeTrackColor: AppTheme.primaryGreen.withValues(alpha: 0.5),
                      activeColor: AppTheme.primaryGreen,
                      onChanged: isToggling
                          ? null
                          : (value) => _toggleTopic(topic, value),
                    ),
                  );
                }),
                // Footer info
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Perubahan akan langsung berlaku. Anda bisa mengubah pengaturan ini kapan saja.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
