import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/settings/gps_settings.dart';
import 'package:geoform_app/services/gps_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadFromPrefs default saat belum ada setelan (jalur snapshot isolate)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = await GpsSettingsService.loadFromPrefs();
    expect(s.maxAccuracyMeters, GpsSettings.defaults().maxAccuracyMeters);
  });

  test('setelan tersimpan terbaca ulang lewat snapshot (foreground → isolate)',
      () async {
    SharedPreferences.setMockInitialValues({});
    await GpsSettingsService()
        .save(GpsSettings.defaults().copyWith(maxAccuracyMeters: 33, trackingIntervalMs: 2000));
    final snap = await GpsSettingsService.loadFromPrefs();
    expect(snap.maxAccuracyMeters, 33);
    expect(snap.trackingIntervalMs, 2000);
  });
}
