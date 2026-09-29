import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/background/background_tracking_service.dart';

/// Cache `_isRunning` di app bisa basi: isolate bisa `stopSelf()` sendiri
/// (heartbeat timeout, lokasi mati, error). Keputusan start harus mengikuti
/// status NYATA dari plugin, bukan cache.
void main() {
  group('decideServiceStart', () {
    test('cache bilang jalan tapi service sudah mati → restart (bug C2)', () {
      expect(
        BackgroundTrackingService.decideServiceStart(
            cachedRunning: true, actualRunning: false),
        ServiceStartDecision.restartStale,
      );
    });

    test('service benar-benar jalan → pakai ulang, jangan start lagi', () {
      expect(
        BackgroundTrackingService.decideServiceStart(
            cachedRunning: true, actualRunning: true),
        ServiceStartDecision.alreadyRunning,
      );
    });

    test('cache basi ke arah sebaliknya (service masih jalan) → pakai ulang', () {
      expect(
        BackgroundTrackingService.decideServiceStart(
            cachedRunning: false, actualRunning: true),
        ServiceStartDecision.alreadyRunning,
      );
    });

    test('keduanya mati → start baru', () {
      expect(
        BackgroundTrackingService.decideServiceStart(
            cachedRunning: false, actualRunning: false),
        ServiceStartDecision.freshStart,
      );
    });
  });

  group('runningFromStatusEvent', () {
    test('laporan berhenti dari isolate → false', () {
      expect(
          BackgroundTrackingService.runningFromStatusEvent({'isRunning': false}),
          isFalse);
    });

    test('laporan jalan → true', () {
      expect(
          BackgroundTrackingService.runningFromStatusEvent({'isRunning': true}),
          isTrue);
    });

    test('event rusak/null → null (abaikan, jangan ubah state)', () {
      expect(BackgroundTrackingService.runningFromStatusEvent(null), isNull);
      expect(BackgroundTrackingService.runningFromStatusEvent({'x': 1}), isNull);
    });
  });
}
