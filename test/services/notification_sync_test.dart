import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/notification_sync_service.dart';

void main() {
  group('stableNotificationId', () {
    test('dari type + object_id', () {
      expect(
        stableNotificationId({'type': 'fire_alerts', 'object_id': '123'}),
        'fire_alerts_123',
      );
    });
    test('fallback type "notif" bila type kosong', () {
      expect(stableNotificationId({'object_id': '7'}), 'notif_7');
    });
    test('null bila tak ada object_id', () {
      expect(stableNotificationId({'type': 'x'}), isNull);
      expect(stableNotificationId(null), isNull);
    });
  });

  group('notificationFromServerItem', () {
    final item = {
      'id': 55,
      'model_name': 'fire_alerts',
      'object_id': '123',
      'action': 'create',
      'company': 3,
      'company_name': 'PT A',
      'title': 'Hotspot',
      'message': 'Ada hotspot',
      'created_at': '2026-08-19T10:00:00Z',
      'is_read': true,
    };

    test('id stabil cocok dengan skema push (model_name_objectid)', () {
      final n = notificationFromServerItem(item);
      expect(n.id, 'fire_alerts_123');
    });
    test('title/body/isRead terpetakan; data bawa server_id + object_id', () {
      final n = notificationFromServerItem(item);
      expect(n.title, 'Hotspot');
      expect(n.body, 'Ada hotspot');
      expect(n.isRead, isTrue);
      expect(n.data!['server_id'], '55');
      expect(n.data!['object_id'], '123');
      expect(n.data!['type'], 'fire_alerts');
    });
  });

  group('newServerItems (dedup)', () {
    test('lewati id yang sudah ada lokal', () {
      final items = [
        {'model_name': 'fire_alerts', 'object_id': '1', 'title': 't', 'message': 'm', 'is_read': false},
        {'model_name': 'fire_alerts', 'object_id': '2', 'title': 't', 'message': 'm', 'is_read': false},
      ];
      final fresh = newServerItems(items, {'fire_alerts_1'});
      expect(fresh.map((n) => n.id), ['fire_alerts_2']);
    });
  });
}
