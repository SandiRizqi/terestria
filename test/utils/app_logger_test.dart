import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/services/logging/app_log.dart';
import 'package:geoform_app/services/logging/diagnostic_mode.dart';
import 'package:geoform_app/utils/app_logger.dart';

class _NoopTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => false;
  @override
  int get tick => 0;
}

void main() {
  late Directory dir;
  late DateTime clock;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('applogger_test');
    clock = DateTime(2026, 9, 29, 8);
    AppLogger.now = () => clock;
    AppLogger.consoleEnabled = false;
    AppLogger.setDiagnosticUntil(null);
    AppLogger.attach(AppLogSink(
      dir: dir,
      source: 'app',
      now: () => clock,
      createTimer: (_, __) => _NoopTimer(),
    ));
  });

  tearDown(() async {
    AppLogger.detach();
    await dir.delete(recursive: true);
  });

  Future<String> contents() async {
    await AppLogger.flush();
    final f = File('${dir.path}/app-20260929.log');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  test('info/warn/error selalu masuk berkas, dengan tag', () async {
    logInfo('sesi mulai', tag: 'SESSION');
    logWarn('akurasi buruk', tag: 'GPS');
    logError('service mati', tag: 'SERVICE');
    final text = await contents();
    expect(text, contains('I SESSION sesi mulai'));
    expect(text, contains('W GPS     akurasi buruk'));
    expect(text, contains('E SERVICE service mati'));
  });

  test('debug TIDAK masuk berkas saat Mode Diagnostik mati', () async {
    logDebug('fix per detik', tag: 'GPS');
    expect(await contents(), isNot(contains('fix per detik')));
  });

  test('debug masuk berkas saat Mode Diagnostik aktif, berhenti saat kedaluwarsa',
      () async {
    AppLogger.setDiagnosticUntil(clock.add(const Duration(hours: 24)));
    logDebug('fix A', tag: 'GPS');
    clock = clock.add(const Duration(hours: 25)); // lewat 24 jam
    logDebug('fix B', tag: 'GPS');
    final all = await contents() +
        (File('${dir.path}/app-20260930.log').existsSync()
            ? File('${dir.path}/app-20260930.log').readAsStringSync()
            : '');
    expect(all, contains('fix A'));
    expect(all, isNot(contains('fix B')));
  });

  test('konsol mati (build release) → tak ada debugPrint', () async {
    final printed = <String?>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => printed.add(m);
    addTearDown(() => debugPrint = original);

    logError('gagal', tag: 'APP');
    expect(printed, isEmpty);

    AppLogger.consoleEnabled = true; // build debug
    logError('gagal', tag: 'APP');
    expect(printed.single, contains('gagal'));
  });

  test('tanpa sink terpasang (mis. sebelum init) → tak error', () {
    AppLogger.detach();
    expect(() => logError('awal'), returnsNormally);
  });

  group('DiagnosticMode', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('enable → aktif 24 jam; disable → mati', () async {
      final now = DateTime(2026, 9, 29, 8);
      final until = await DiagnosticMode.enable(now: now);
      expect(until, now.add(const Duration(hours: 24)));
      expect(await DiagnosticMode.load(), until);

      await DiagnosticMode.disable();
      expect(await DiagnosticMode.load(), isNull);
    });

    test('isActive memperhitungkan kedaluwarsa', () {
      final now = DateTime(2026, 9, 29, 8);
      expect(DiagnosticMode.isActive(null, now), isFalse);
      expect(DiagnosticMode.isActive(now.add(const Duration(minutes: 1)), now),
          isTrue);
      expect(DiagnosticMode.isActive(now.subtract(const Duration(seconds: 1)), now),
          isFalse);
    });
  });
}
