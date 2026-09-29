import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/logging/log_exporter.dart';
import 'package:geoform_app/services/tracking/tracking_session.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';

Project _proj(String id, String name) => Project(
      id: id,
      name: name,
      description: '',
      geometryType: GeometryType.polygon,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  final now = DateTime(2026, 9, 29, 8, 30, 5);

  test('snapshot: status engine/service, tiap sesi, izin', () {
    final m = TrackingSessionManager(maxConcurrent: 3);
    m.start(_proj('a', 'Jalan A'));
    m.ingest(GeoPoint(
        latitude: -6.2, longitude: 106.8, timestamp: DateTime(2026, 9, 29, 8, 30)));
    m.start(_proj('b', 'Blok B'), source: TrackSource.emlid);
    m.finish('b');

    final text = buildSnapshotText(
      now: now,
      sessions: m.activeSessions,
      maxConcurrent: m.maxConcurrent,
      engineActive: true,
      serviceRunning: false,
      status: {'permission_locationAlways': 'PermissionStatus.denied'},
    );
    expect(text, contains('Engine: active'));
    expect(text, contains('Background service: STOPPED'));
    expect(text, contains('"Jalan A" recording source=phone polygon points=1'));
    expect(text, contains('last point 5 s ago'));
    expect(text, contains('"Blok B" pendingSave source=emlid'));
    expect(text, contains('permission_locationAlways: PermissionStatus.denied'));
  });

  test('info: OS, provider, versi DB, setelan GPS', () {
    final text = buildInfoText(
      now: now,
      os: 'android',
      osVersion: '14 (API 34)',
      provider: 'phone',
      dbVersion: 5,
      gpsSettings: {'distanceFilterMeters': 2.0, 'trackingIntervalMs': 1000},
    );
    expect(text, contains('OS: android 14 (API 34)'));
    expect(text, contains('GPS provider: phone'));
    expect(text, contains('DB version: 5'));
    expect(text, contains('distanceFilterMeters = 2.0'));
  });

  test('latestGpsCsv: 3 berkas terbaru berdasarkan nama', () {
    final files = [
      'gps_20260927_080000.csv',
      'gps_20260929_070000.csv',
      'gps_20260928_090000.csv',
      'gps_20260929_081500.csv',
    ].map((n) => File('/x/$n')).toList();
    expect(latestGpsCsv(files).map((f) => f.uri.pathSegments.last), [
      'gps_20260929_081500.csv',
      'gps_20260929_070000.csv',
      'gps_20260928_090000.csv',
    ]);
  });

  test('zip berisi log app+bg, CSV GPS, info & snapshot (tanpa rahasia)',
      () async {
    final tmp = await Directory.systemTemp.createTemp('bundle');
    addTearDown(() => tmp.delete(recursive: true));
    final logs = Directory('${tmp.path}/logs')..createSync();
    final gps = Directory('${tmp.path}/gps')..createSync();
    File('${logs.path}/app-20260929.log').writeAsStringSync('I ENGINE aktif\n');
    File('${logs.path}/bg-20260929.log').writeAsStringSync('W SERVICE mati\n');
    File('${gps.path}/gps_20260929_080000.csv').writeAsStringSync('t,lat,lon\n');

    final zip = await buildLogBundle(
      outDir: tmp,
      now: now,
      logFiles: logs.listSync().whereType<File>().toList(),
      gpsFiles: gps.listSync().whereType<File>().toList(),
      infoText: 'OS: android',
      snapshotText: 'Authorization: Bearer RAHASIA99',
    );

    expect(zip.uri.pathSegments.last, 'terestria-log-20260929-083005.zip');
    final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, {
      'logs/app-20260929.log',
      'logs/bg-20260929.log',
      'gps/gps_20260929_080000.csv',
      'info.txt',
      'snapshot.txt',
    });
    final snapshot = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'snapshot.txt').content
            as List<int>);
    expect(snapshot, isNot(contains('RAHASIA99')));
  });
}
