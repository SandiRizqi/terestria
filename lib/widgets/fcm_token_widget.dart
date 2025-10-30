import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_messaging_service.dart';

class FCMTokenWidget extends StatelessWidget {
  const FCMTokenWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final fcmToken = FirebaseMessagingService().fcmToken;

    if (fcmToken == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'FCM Token',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fcmToken));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Token copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  tooltip: 'Copy token',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              fcmToken,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
                fontFamily: 'monospace',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Gunakan token ini untuk testing di Firebase Console',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
