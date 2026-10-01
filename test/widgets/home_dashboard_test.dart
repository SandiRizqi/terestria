import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/screens/readiness/field_readiness_screen.dart';
import 'package:geoform_app/services/auto_sync_service.dart';
import 'package:geoform_app/services/readiness/field_readiness.dart';
import 'package:geoform_app/widgets/home/home_menu.dart';
import 'package:geoform_app/widgets/home/home_status_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 9, 29, 8);

ReadinessInputs _inputs({
  bool? battery = true,
  int unsynced = 0,
  int photos = 0,
  GeoPoint? fix,
}) =>
    ReadinessInputs(
      isAndroid: true,
      isIOS: false,
      now: _now,
      locationServiceOn: true,
      locationAccess: LocationAccess.whileInUse,
      ignoringBatteryOptimizations: battery,
      notificationsAllowed: true,
      manufacturer: 'samsung',
      freeBytes: 3 * 1024 * 1024 * 1024,
      lastFix: fix,
      gpsTested: fix != null,
      basemapName: 'OSM',
      offline: fix == null
          ? OfflineCoverage.noLocation
          : OfflineCoverage.available,
      unsyncedRecords: unsynced,
      pendingPhotos: photos,
    );

void _phone(WidgetTester tester, {double textScale = 1}) {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 1.5]) {
    testWidgets('menu beranda 3 kolom muat di 360 dp (teks ×$scale)',
        (tester) async {
      _phone(tester, textScale: scale);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const HomeSectionLabel('Account & device'),
              HomeMenuGrid(children: [
                for (final t in ['Notifications', 'Location', 'Settings',
                  'Profile'])
                  HomeMenuCard(
                    icon: Icons.settings_rounded,
                    title: t,
                    description: 'Preferences',
                    color: Colors.green,
                    badge: t == 'Notifications' ? 120 : null,
                    onTap: () {},
                  ),
              ]),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });
  }

  testWidgets(
      'kartu status: GPS belum diuji → "No problems found" + antrean sync '
      '(offline → tombol mati)', (tester) async {
    _phone(tester);
    var readinessOpened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          HomeStatusSection(
            onOpenProject: (_) {},
            onOpenReadiness: () => readinessOpened++,
            collect: () async => _inputs(unsynced: 12, photos: 30),
            lastGpsTest: () => null,
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ready for the field'), findsNothing);
    expect(find.text('No problems found'), findsOneWidget);
    expect(find.text('Tap to test GPS signal'), findsOneWidget);
    expect(find.text('12 records · 30 photos waiting'), findsOneWidget);
    expect(find.text('Offline — your data is safe on this phone'),
        findsOneWidget);
    final sync = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sync now'));
    expect(sync.onPressed, isNull, reason: 'offline');

    await tester.tap(find.text('No problems found'));
    expect(readinessOpened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kartu status: uji GPS lengkap terakhir lolos → "Ready for the '
      'field"', (tester) async {
    _phone(tester);
    final tested = gpsTestResultOf(_inputs(
        fix: GeoPoint(
            latitude: -6.2, longitude: 106.8, accuracy: 3.2, timestamp: _now)))!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeStatusSection(
          onOpenProject: (_) {},
          onOpenReadiness: () {},
          collect: () async => _inputs(),
          lastGpsTest: () => tested,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ready for the field'), findsOneWidget);
    expect(find.text('Permissions, GPS, battery and storage look good'),
        findsOneWidget);
  });

  test('status auto-sync gagal menyebut alasan pertama', () {
    final run = AutoSyncRun(
      at: DateTime(2026, 9, 30, 8, 5),
      ok: false,
      summary: 'Data: 0/2 synced',
      reasons: const ['Blok A: not accepting data (2×)', 'x'],
    );
    expect(lastAutoSyncSubtitle(run, '08.05'),
        'Last auto-sync 08.05 failed: Blok A: not accepting data (2×)');
    expect(
        lastAutoSyncSubtitle(
            AutoSyncRun(at: DateTime(2026), ok: false, summary: 'Server not reachable'),
            '08.05'),
        'Last auto-sync 08.05: Server not reachable');
  });

  testWidgets('kartu status: optimasi baterai → peringatan; semua tersinkron',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeStatusSection(
          onOpenProject: (_) {},
          onOpenReadiness: () {},
          collect: () async => _inputs(battery: false),
          lastGpsTest: () => null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 item needs attention'), findsOneWidget);
    expect(find.text('Battery optimization'), findsOneWidget);
    expect(find.text('Everything is synced'), findsOneWidget);
  });

  testWidgets('layar Readiness: ringkasan, butir, uji GPS ulang',
      (tester) async {
    _phone(tester);
    var gpsTests = 0;
    Future<ReadinessInputs> collect(
        {bool testGps = true, GeoPoint? previousFix}) async {
      if (testGps) gpsTests++;
      return _inputs(
        battery: false,
        fix: testGps
            ? GeoPoint(
                latitude: -6.2,
                longitude: 106.8,
                accuracy: 3.2,
                timestamp: _now)
            : previousFix,
      );
    }

    await tester.pumpWidget(
        MaterialApp(home: FieldReadinessScreen(collect: collect)));
    await tester.pumpAndSettle();

    expect(find.text('1 item needs attention'), findsOneWidget);
    expect(find.text('Battery optimization'), findsOneWidget);
    expect(find.textContaining('Sleeping apps'), findsOneWidget,
        reason: 'panduan Samsung tampil');
    expect(find.textContaining('±3.2 m'), findsOneWidget);
    expect(gpsTests, 1);

    await tester.scrollUntilVisible(find.text('Test again'), 200);
    await tester.tap(find.text('Test again'));
    await tester.pumpAndSettle();
    expect(gpsTests, 2);
    expect(tester.takeException(), isNull);
  });
}
