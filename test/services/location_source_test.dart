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
}
