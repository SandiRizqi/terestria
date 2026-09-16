import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/settings/app_settings.dart';

/// Setting batas project tracking bersamaan: default 3, rentang 3–7.
void main() {
  test('default maxConcurrentTracking = 3', () {
    expect(AppSettings.defaults().maxConcurrentTracking, 3);
  });

  test('konstanta rentang 3..7', () {
    expect(AppSettings.minConcurrentTracking, 3);
    expect(AppSettings.maxConcurrentTrackingLimit, 7);
  });

  test('fromJson clamp ke rentang', () {
    expect(AppSettings.fromJson({'maxConcurrentTracking': 1}).maxConcurrentTracking, 3);
    expect(AppSettings.fromJson({'maxConcurrentTracking': 99}).maxConcurrentTracking, 7);
    expect(AppSettings.fromJson({'maxConcurrentTracking': 5}).maxConcurrentTracking, 5);
  });

  test('toJson → fromJson round-trip', () {
    final s = AppSettings.defaults().copyWith(maxConcurrentTracking: 6);
    expect(AppSettings.fromJson(s.toJson()).maxConcurrentTracking, 6);
  });
}
