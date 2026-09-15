import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geoform_app/services/background/permission_service.dart';

/// "Always" hanya diminta SEKALI: bila belum pernah ditanya DAN statusnya masih
/// denied. Kalau sudah pernah ditanya (user memilih When-In-Use), jangan
/// prompt lagi tiap masuk data collection.
void main() {
  test('minta Always: belum pernah + masih denied → true', () {
    expect(
        PermissionService.shouldRequestAlways(
            alreadyAsked: false, alwaysDenied: true),
        isTrue);
  });

  test('sudah pernah ditanya → jangan minta lagi (false)', () {
    expect(
        PermissionService.shouldRequestAlways(
            alreadyAsked: true, alwaysDenied: true),
        isFalse);
  });

  test('sudah Always (tak denied) → tak perlu minta (false)', () {
    expect(
        PermissionService.shouldRequestAlways(
            alreadyAsked: false, alwaysDenied: false),
        isFalse);
  });

  group('backgroundNeedsAlways', () {
    test('iOS + hanya When-In-Use → perlu peringatan (true)', () {
      expect(
          PermissionService.backgroundNeedsAlways(
              isIOS: true, permission: LocationPermission.whileInUse),
          isTrue);
    });

    test('iOS + Always → tidak perlu peringatan (false)', () {
      expect(
          PermissionService.backgroundNeedsAlways(
              isIOS: true, permission: LocationPermission.always),
          isFalse);
    });

    test('Android + When-In-Use → cukup (false, pakai foreground service)', () {
      expect(
          PermissionService.backgroundNeedsAlways(
              isIOS: false, permission: LocationPermission.whileInUse),
          isFalse);
    });
  });
}
