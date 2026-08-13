import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/screens/settings/gps_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GpsSettingsScreen render kontrol dasar + tombol restart',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: GpsSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Filter Akurasi'), findsOneWidget);
    expect(find.text('Smoothing (EMA α)'), findsOneWidget);
    expect(find.byType(Slider), findsWidgets);

    // Tombol restart ada di bawah (ListView lazy) — scroll dulu.
    await tester.scrollUntilVisible(find.text('Restart tracking now'), 500);
    expect(find.text('Restart tracking now'), findsOneWidget);
  });
}
