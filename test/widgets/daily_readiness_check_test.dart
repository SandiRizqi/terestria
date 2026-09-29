import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/readiness/field_readiness.dart';
import 'package:geoform_app/widgets/readiness/daily_readiness_check.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReadinessInputs _inputs({bool? battery}) => ReadinessInputs(
      isAndroid: true,
      isIOS: false,
      now: DateTime(2026, 9, 29, 8),
      locationServiceOn: true,
      locationAccess: LocationAccess.whileInUse,
      ignoringBatteryOptimizations: battery,
      notificationsAllowed: true,
      freeBytes: 2 * 1024 * 1024 * 1024,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<bool>> run(WidgetTester tester, ReadinessInputs inputs,
      {required DateTime day, String? tap, int times = 1}) async {
    final results = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await maybeShowDailyReadinessCheck(
              context,
              collect: () async => inputs,
              now: () => day)),
          child: const Text('start'),
        ),
      ),
    ));
    for (var i = 0; i < times; i++) {
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      if (tap != null && find.text(tap).evaluate().isNotEmpty) {
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      }
    }
    return results;
  }

  testWidgets('masalah baterai → sheet sekali per hari; Start anyway lanjut',
      (tester) async {
    final day = DateTime(2026, 9, 29, 7);
    final r = await run(tester, _inputs(battery: false),
        day: day, tap: 'Start anyway', times: 2);
    // Klik pertama: sheet muncul lalu "Start anyway" → true. Klik kedua di
    // hari yang sama: tak ada sheet, langsung true.
    expect(r, [true, true]);
  });

  testWidgets('semua baik → tanpa sheet', (tester) async {
    final r = await run(tester, _inputs(battery: true),
        day: DateTime(2026, 9, 29, 7));
    expect(r, [true]);
    expect(find.text('Before you start'), findsNothing);
  });

  testWidgets('sheet ditutup tanpa pilihan → batal Start', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await maybeShowDailyReadinessCheck(
              context,
              collect: () async => _inputs(battery: false),
              now: () => DateTime(2026, 9, 30, 7))),
          child: const Text('start'),
        ),
      ),
    ));
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Before you start'), findsOneWidget);
    expect(find.textContaining('Battery optimization'), findsOneWidget);
    // Tutup sheet (tap di luar).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets('pemeriksaan gagal → Start tetap jalan', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await maybeShowDailyReadinessCheck(
              context,
              collect: () async => throw StateError('plugin'),
              now: () => DateTime(2026, 10, 1))),
          child: const Text('start'),
        ),
      ),
    ));
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });
}
