// ignore_for_file: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/connectivity_service.dart';

void main() {
  test('startMonitoring berulang tidak menumpuk timer; stop aman diulang', () {
    fakeAsync((async) {
      final svc = ConnectivityService();
      svc.startMonitoring();
      svc.startMonitoring();
      svc.startMonitoring();
      // Satu timer periodik (+ lookup DNS yang tertunda) — dulu 3 timer.
      expect(async.periodicTimerCount, 1);
      expect(svc.isMonitoring, isTrue);

      svc.stopMonitoring();
      svc.stopMonitoring();
      expect(async.periodicTimerCount, 0);
      expect(svc.isMonitoring, isFalse);

      // Stream tetap bisa didengar setelah stop (dulu ditutup permanen).
      expect(() => svc.connectivityStream.listen((_) {}).cancel(),
          returnsNormally);
      svc.startMonitoring();
      expect(async.periodicTimerCount, 1);
      svc.stopMonitoring();
    });
  });
}
