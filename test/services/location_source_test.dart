import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/location_service_v2.dart';

void main() {
  group('shouldUseLiveEmlidPoint', () {
    test('true bila Emlid dipilih, konek, streaming, dan ada titik live', () {
      expect(
        shouldUseLiveEmlidPoint(
          provider: LocationProvider.emlid,
          isConnected: true,
          isStreaming: true,
          hasLastEmlidPoint: true,
        ),
        isTrue,
      );
    });

    test('false bila belum ada titik Emlid live (jangan pakai prefs phone)', () {
      expect(
        shouldUseLiveEmlidPoint(
          provider: LocationProvider.emlid,
          isConnected: true,
          isStreaming: true,
          hasLastEmlidPoint: false,
        ),
        isFalse,
      );
    });

    test('false bila Emlid stale / tidak streaming', () {
      expect(
        shouldUseLiveEmlidPoint(
          provider: LocationProvider.emlid,
          isConnected: true,
          isStreaming: false,
          hasLastEmlidPoint: true,
        ),
        isFalse,
      );
    });

    test('false bila provider phone', () {
      expect(
        shouldUseLiveEmlidPoint(
          provider: LocationProvider.phone,
          isConnected: true,
          isStreaming: true,
          hasLastEmlidPoint: true,
        ),
        isFalse,
      );
    });
  });

  group('phoneFixTier', () {
    test('akurasi <= goodFix → autonomous', () {
      expect(phoneFixTier(15, 20), 'autonomous');
      expect(phoneFixTier(20, 20), 'autonomous');
    });
    test('akurasi > goodFix → null (tak layak)', () {
      expect(phoneFixTier(35, 20), isNull);
    });
  });

  group('meetsFixRequirement', () {
    test('any selalu terpenuhi', () {
      expect(meetsFixRequirement(FixQuality.any, null), isTrue);
      expect(meetsFixRequirement(FixQuality.any, 'autonomous'), isTrue);
    });
    test('autonomous terpenuhi hanya bila tier autonomous+', () {
      expect(meetsFixRequirement(FixQuality.autonomous, 'autonomous'), isTrue);
      expect(meetsFixRequirement(FixQuality.autonomous, null), isFalse);
    });
    test('float/fix tak pernah terpenuhi oleh phone (autonomous)', () {
      expect(meetsFixRequirement(FixQuality.float, 'autonomous'), isFalse);
      expect(meetsFixRequirement(FixQuality.fix, 'autonomous'), isFalse);
    });
  });
}
