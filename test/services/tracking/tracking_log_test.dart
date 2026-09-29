import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/logging/app_log.dart';
import 'package:geoform_app/services/tracking/tracking_engine.dart';
import 'package:geoform_app/services/tracking/tracking_log_summary.dart';
import 'package:geoform_app/services/tracking/tracking_session.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';
import 'package:geoform_app/utils/app_logger.dart';

Project _proj(String id, String name) => Project(
      id: id,
      name: name,
      description: '',
      geometryType: GeometryType.line,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

GeoPoint _fix(int sec, {double acc = 4, bool recordable = true}) => GeoPoint(
    latitude: -6.2,
    longitude: 106.8 + sec * 1e-4,
    accuracy: acc,
    recordable: recordable,
    timestamp: DateTime(2026, 9, 29, 8, 0, sec));

class _NoopTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => false;
  @override
  int get tick => 0;
}

void main() {
  group('TrackingLogSummary (ringkasan per menit)', () {
    final t0 = DateTime(2026, 9, 29, 8);

    test('belum 60 dtk → null; tepat 60 dtk → ringkasan fix & titik per sesi',
        () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      final sum = TrackingLogSummary(start: t0);
      m.start(_proj('a', 'Jalan A'));
      m.start(_proj('b', 'Blok B'));
      for (var i = 0; i < 4; i++) {
        final p = _fix(i, acc: [3.0, 4.0, 5.0, 30.0][i], recordable: i < 3);
        sum.onFix(TrackSource.phone, p);
        m.ingest(p);
      }

      expect(sum.maybeSummary(t0.add(const Duration(seconds: 59)),
          m.activeSessions), isNull);
      final text = sum.maybeSummary(
          t0.add(const Duration(seconds: 60)), m.activeSessions)!;
      expect(text, contains('HP 4 fix'));
      expect(text, contains('1 ditolak'));
      expect(text, contains('median ±4.5 m'));
      expect(text, contains('"Jalan A" +3 (total 3)'));
      expect(text, contains('"Blok B" +3 (total 3)'));
    });

    test('jendela berikutnya menghitung ulang dari nol', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      final sum = TrackingLogSummary(start: t0);
      m.start(_proj('a', 'A'));
      m.ingest(_fix(0));
      sum.onFix(TrackSource.phone, _fix(0));
      sum.maybeSummary(t0.add(const Duration(minutes: 1)), m.activeSessions);

      m.ingest(_fix(1));
      sum.onFix(TrackSource.phone, _fix(1));
      final text = sum.maybeSummary(
          t0.add(const Duration(minutes: 2)), m.activeSessions)!;
      expect(text, contains('HP 1 fix'));
      expect(text, contains('"A" +1 (total 2)'));
    });

    test('tak ada sesi merekam → tak ada ringkasan', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      final sum = TrackingLogSummary(start: t0);
      m.start(_proj('a', 'A'));
      m.pause('a');
      expect(sum.maybeSummary(t0.add(const Duration(minutes: 5)),
          m.activeSessions), isNull);
    });

    test('sesi merekam tanpa fix → ringkasan menyebut 0 fix (tanda GPS diam)',
        () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      final sum = TrackingLogSummary(start: t0);
      m.start(_proj('a', 'A'));
      final text = sum.maybeSummary(
          t0.add(const Duration(minutes: 1)), m.activeSessions)!;
      expect(text, contains('0 fix'));
      expect(text, contains('"A" +0 (total 0)'));
    });
  });

  group('event berkas log', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('trk_log');
      AppLogger.consoleEnabled = false;
      AppLogger.setDiagnosticUntil(null);
      AppLogger.attach(AppLogSink(
          dir: dir, source: 'app', createTimer: (_, __) => _NoopTimer()));
    });
    tearDown(() async {
      AppLogger.detach();
      await dir.delete(recursive: true);
    });

    Future<String> logText() async {
      await AppLogger.flush();
      final files = dir.listSync().whereType<File>();
      return files.map((f) => f.readAsStringSync()).join();
    }

    test('transisi sesi tercatat sekali per kejadian (bukan per titik)',
        () async {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a', 'Jalan A'), source: TrackSource.emlid);
      for (var i = 0; i < 20; i++) {
        m.ingest(_fix(i), source: TrackSource.emlid);
      }
      m.pause('a');
      m.resume('a');
      m.finish('a');
      m.stop('a');

      final text = await logText();
      expect(text, contains('I SESSION Start "Jalan A"'));
      expect(text, contains('sumber=emlid'));
      expect(text, contains('I SESSION Jeda "Jalan A"'));
      expect(text, contains('I SESSION Lanjut "Jalan A"'));
      expect(text, contains('I SESSION Stop "Jalan A" → draft (20 titik)'));
      expect(text, contains('I SESSION Lepas "Jalan A" (20 titik)'));
      expect('SESSION'.allMatches(text).length, 5);
    });

    test('engine mencatat aktif/idle, dan gagal start sebagai warn', () async {
      final m = TrackingSessionManager(maxConcurrent: 3);
      var ok = false;
      final e = TrackingEngine(
        manager: m,
        startService: () async => ok,
        stopService: () async {},
        sendHeartbeat: () {},
        isServiceRunning: () => false,
        periodicTimer: (_, __) => _NoopTimer(),
      )..attach();

      m.start(_proj('a', 'A'));
      await e.ensureRunning();
      m.finish('a');
      await Future<void>.delayed(Duration.zero);
      e.detach();

      final text = await logText();
      expect(text, contains('I ENGINE  Aktif (1 merekam)'));
      expect(text, contains('W ENGINE  Service gagal dinyalakan'));
      expect(text, contains('I ENGINE  Idle'));
    });
  });
}
