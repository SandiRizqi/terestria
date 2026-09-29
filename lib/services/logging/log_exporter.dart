import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/app_logger.dart';
import '../background/permission_service.dart';
import '../database_service.dart';
import '../gps_settings_service.dart';
import '../location_service_v2.dart';
import '../tracking/tracking_engine.dart';
import '../tracking/tracking_session.dart';
import '../tracking/tracking_session_manager.dart';
import 'app_log.dart';
import 'log_redactor.dart';
import 'log_setup.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime t) =>
    '${logDayKey(t)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

/// Kondisi tracking saat log dibagikan — jawaban cepat "kenapa tak merekam?".
String buildSnapshotText({
  required DateTime now,
  required Iterable<TrackingSession> sessions,
  required int maxConcurrent,
  required bool engineActive,
  required bool serviceRunning,
  required Map<String, dynamic> status,
}) {
  final list = sessions.toList();
  final b = StringBuffer()
    ..writeln('Snapshot ${now.toIso8601String()}')
    ..writeln('Engine: ${engineActive ? 'aktif' : 'idle'}')
    ..writeln('Service background: ${serviceRunning ? 'berjalan' : 'MATI'}')
    ..writeln('Batas project bersamaan: $maxConcurrent')
    ..writeln()
    ..writeln('Sesi (${list.length}):');
  for (final s in list) {
    final last = s.points.isEmpty ? null : s.points.last.timestamp;
    final ago = last == null
        ? 'belum ada titik'
        : 'titik terakhir ${now.difference(last).inSeconds} dtk lalu';
    b.writeln('- "${s.project.name}" ${s.state.name} sumber=${s.source.name} '
        '${s.project.geometryType.name} titik=${s.pointCount} '
        'mulai=${s.startedAt.toIso8601String()} $ago');
  }
  b
    ..writeln()
    ..writeln('Izin & perangkat:');
  for (final e in status.entries) {
    b.writeln('- ${e.key}: ${e.value}');
  }
  return b.toString();
}

/// Info perangkat & konfigurasi.
String buildInfoText({
  required DateTime now,
  required String os,
  required String osVersion,
  required String provider,
  required int dbVersion,
  required Map<String, dynamic> gpsSettings,
}) {
  final b = StringBuffer()
    ..writeln('Terestria — log diagnostik')
    ..writeln('Dibuat: ${now.toIso8601String()}')
    ..writeln('OS: $os $osVersion')
    ..writeln('Provider GPS: $provider')
    ..writeln('Versi DB: $dbVersion')
    ..writeln()
    ..writeln('Setelan GPS:');
  for (final e in gpsSettings.entries) {
    b.writeln('- ${e.key} = ${e.value}');
  }
  return b.toString();
}

/// [n] CSV log GPS terbaru (nama `gps_yyyyMMdd_HHmmss.csv` terurut waktu).
List<File> latestGpsCsv(List<File> files, {int n = 3}) {
  final sorted = List.of(files)
    ..sort((a, b) => b.uri.pathSegments.last.compareTo(a.uri.pathSegments.last));
  return sorted.take(n).toList();
}

/// Susun zip: `logs/*`, `gps/*`, `info.txt`, `snapshot.txt`. Teks info &
/// snapshot ikut disaring [LogRedactor] (log sudah disaring saat ditulis).
Future<File> buildLogBundle({
  required Directory outDir,
  required DateTime now,
  required List<File> logFiles,
  required List<File> gpsFiles,
  required String infoText,
  required String snapshotText,
}) async {
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));

  for (final f in logFiles) {
    add('logs/${f.uri.pathSegments.last}', await f.readAsBytes());
  }
  for (final f in gpsFiles) {
    add('gps/${f.uri.pathSegments.last}', await f.readAsBytes());
  }
  add('info.txt', utf8.encode(LogRedactor.redact(infoText)));
  add('snapshot.txt', utf8.encode(LogRedactor.redact(snapshotText)));

  final out = File('${outDir.path}/terestria-log-${_stamp(now)}.zip');
  await out.writeAsBytes(ZipEncoder().encode(archive));
  return out;
}

/// Kumpulkan semua bahan dari app, buat zip di folder temp, lalu buka share
/// sheet. Error dilempar ke pemanggil (UI menampilkan pesannya).
///
/// [sharePositionOrigin] wajib (`shareOriginFor(context)` dari tombol yang
/// ditekan): iOS menolak share sheet dengan rect asal nol.
Future<void> exportAndShareLogs({required Rect sharePositionOrigin}) async {
  final now = DateTime.now();
  logInfo('Ekspor log dimulai', tag: 'LOG');
  await AppLogger.flush();

  final logsDir = await logsDirectory();
  final logFiles = await logsDir.exists()
      ? logsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList()
      : <File>[];

  final location = LocationServiceV2();
  final manager = TrackingSessionManager.instance;
  final status = await PermissionService.getDetailedStatus();

  final zip = await buildLogBundle(
    outDir: await getTemporaryDirectory(),
    now: now,
    logFiles: logFiles,
    gpsFiles: latestGpsCsv(await location.getGpsLogFiles()),
    infoText: buildInfoText(
      now: now,
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      provider: location.currentProvider.name,
      dbVersion: DatabaseService.schemaVersion,
      gpsSettings: GpsSettingsService().settings.toJson(),
    ),
    snapshotText: buildSnapshotText(
      now: now,
      sessions: manager.activeSessions,
      maxConcurrent: manager.maxConcurrent,
      engineActive: TrackingEngine.instance.isActive,
      serviceRunning: location.isBackgroundServiceRunning,
      status: status,
    ),
  );
  logInfo('Ekspor log: ${zip.uri.pathSegments.last} '
      '(${logFiles.length} log)', tag: 'LOG');

  await Share.shareXFiles(
    [XFile(zip.path, mimeType: 'application/zip')],
    subject: 'Log Terestria ${_stamp(now)}',
    sharePositionOrigin: sharePositionOrigin,
  );
}
