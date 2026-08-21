import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/notification_model.dart';
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
    test('map (GeoJSON) diteruskan ke data → tombol peta muncul', () {
      final withMap = {...item, 'map': '{"type":"FeatureCollection"}'};
      final n = notificationFromServerItem(withMap);
      expect(n.data!['map'], '{"type":"FeatureCollection"}');
    });
    test('tanpa map / map null → data tak punya key "map"', () {
      expect(notificationFromServerItem(item).data!.containsKey('map'), isFalse);
      final nullMap = {...item, 'map': null};
      expect(notificationFromServerItem(nullMap).data!.containsKey('map'), isFalse);
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

  group('enrichableFromServer (backfill map baris lama)', () {
    NotificationModel local({Map<String, dynamic>? data, bool isRead = true}) =>
        NotificationModel(
          id: 'fire_alerts_1', title: 't', body: 'm',
          data: data ?? {'type': 'fire_alerts', 'object_id': '1'},
          receivedAt: DateTime.utc(2026, 1, 1), isRead: isRead,
        );
    final serverWithMap = {
      'model_name': 'fire_alerts', 'object_id': '1', 'title': 't',
      'message': 'm', 'is_read': false, 'map': '{"type":"FeatureCollection"}',
    };

    test('lokal tanpa map + server punya map → enrich, isRead lokal dipertahankan', () {
      final l = local(isRead: true);
      final out = enrichableFromServer([serverWithMap], {l.id: l});
      expect(out.length, 1);
      expect(out.first.data!['map'], '{"type":"FeatureCollection"}');
      expect(out.first.isRead, isTrue); // TIDAK direset oleh server is_read:false
    });

    test('lokal sudah punya map → tidak di-enrich (idempoten)', () {
      final l = local(data: {'type': 'fire_alerts', 'object_id': '1', 'map': 'x'});
      expect(enrichableFromServer([serverWithMap], {l.id: l}), isEmpty);
    });

    test('id tak ada lokal → dilewati', () {
      expect(enrichableFromServer([serverWithMap], {}), isEmpty);
    });

    test('server tanpa map → tak ada yang di-enrich', () {
      final l = local();
      final noMap = {...serverWithMap}..remove('map');
      expect(enrichableFromServer([noMap], {l.id: l}), isEmpty);
    });
  });
}
