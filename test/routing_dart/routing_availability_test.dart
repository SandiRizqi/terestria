import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_service.dart';

/// Logika gate ketersediaan routing lintas-platform (dipakai RoutingService &
/// RoutingDataManager). Android selalu; iOS bila mesin Dart diaktifkan.
void main() {
  test('Android → selalu tersedia', () {
    expect(
        routingAvailable(isAndroid: true, isIos: false, iosEngineEnabled: true),
        isTrue);
    expect(
        routingAvailable(
            isAndroid: true, isIos: false, iosEngineEnabled: false),
        isTrue);
  });

  test('iOS → tersedia hanya bila mesin Dart aktif', () {
    expect(
        routingAvailable(isAndroid: false, isIos: true, iosEngineEnabled: true),
        isTrue);
    expect(
        routingAvailable(
            isAndroid: false, isIos: true, iosEngineEnabled: false),
        isFalse);
  });

  test('platform lain → tidak tersedia', () {
    expect(
        routingAvailable(
            isAndroid: false, isIos: false, iosEngineEnabled: true),
        isFalse);
  });

  test('flag iOS engine default aktif', () {
    expect(RoutingService.iosEngineEnabled, isTrue);
  });
}
