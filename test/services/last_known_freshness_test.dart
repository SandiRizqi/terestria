import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/background/phone_gps_service.dart';

void main() {
  group('isLastKnownFresh', () {
    final now = DateTime(2026, 8, 13, 12, 0, 0);

    test('fresh: fix 30 detik lalu, batas 120s → true', () {
      expect(
        isLastKnownFresh(now.subtract(const Duration(seconds: 30)), now, 120),
        isTrue,
      );
    });

    test('stale: fix 5 menit lalu, batas 120s → false', () {
      expect(
        isLastKnownFresh(now.subtract(const Duration(minutes: 5)), now, 120),
        isFalse,
      );
    });

    test('tepat di batas dianggap fresh', () {
      expect(
        isLastKnownFresh(now.subtract(const Duration(seconds: 120)), now, 120),
        isTrue,
      );
    });

    test('timestamp masa depan (clock skew) tetap fresh', () {
      expect(
        isLastKnownFresh(now.add(const Duration(seconds: 5)), now, 120),
        isTrue,
      );
    });
  });
}
