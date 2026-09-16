import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/tracking/tracking_notification.dart';
import 'package:geoform_app/services/tracking/tracking_persistence_coordinator.dart';

/// Helper murni untuk persistensi & notifikasi multi-sesi (koordinator penuh
/// butuh DB/plugin → diverifikasi manual).
void main() {
  group('trackingNotificationText', () {
    test('0 sesi → null', () => expect(trackingNotificationText(0), isNull));
    test('1 sesi', () {
      expect(trackingNotificationText(1), 'Tracking 1 project aktif');
    });
    test('banyak sesi', () {
      expect(trackingNotificationText(3), 'Tracking 3 project aktif');
    });
  });

  group('pendingAppendCount', () {
    test('titik baru sejak flush', () {
      expect(pendingAppendCount(5, 3), 2);
      expect(pendingAppendCount(3, 3), 0);
      expect(pendingAppendCount(2, 5), 0); // tak pernah negatif
    });
  });

  group('removedIds', () {
    test('sesi yang berhenti terdeteksi', () {
      expect(removedIds({'a', 'b'}, {'a'}), {'b'});
      expect(removedIds({'a'}, {'a', 'b'}), <String>{});
      expect(removedIds({'a', 'b'}, {'a', 'b'}), <String>{});
    });
  });
}
