import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/api_config.dart';
import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../../utils/app_logger.dart';
import '../export/geo_export.dart';
import '../photo_sync_service.dart';
import '../storage_service.dart';
import '../tracking/tracking_session.dart';
import '../tracking/tracking_session_manager.dart';

/// Ringkasan cadangan yang dibuat.
class LocalBackupResult {
  final File file;
  final int projects;
  final int records;
  final int unsyncedRecords;
  final int photos;
  final List<String> missingPhotos;
  final int trackingSessions;
  final int bytes;

  const LocalBackupResult({
    required this.file,
    required this.projects,
    required this.records,
    required this.unsyncedRecords,
    required this.photos,
    required this.missingPhotos,
    required this.trackingSessions,
    required this.bytes,
  });

  @override
  String toString() => 'projects=$projects records=$records '
      '(unsynced=$unsyncedRecords) photos=$photos '
      'missingPhotos=${missingPhotos.length} sessions=$trackingSessions '
      'bytes=$bytes';
}

/// Cadangan lokal (ZIP) sebelum logout — logout menghapus SEMUA data di HP.
///
/// Isi: per project `project.json`, `records.json` (format app), `.geojson`
/// (siap dibuka di QGIS), dan foto yang BELUM ter-upload; plus sesi tracking
/// yang belum disimpan, `manifest.json`, dan `README.txt`. Foto ditulis
/// streaming tanpa kompresi (JPEG) sehingga tak dimuat ke RAM.
class LocalBackupService {
  LocalBackupService({
    Future<List<Project>> Function()? loadProjects,
    Future<List<GeoData>> Function(String projectId)? loadRecords,
    List<TrackingSession> Function()? trackingSessions,
    Future<Directory> Function()? outputDir,
    DateTime Function()? now,
  })  : _loadProjects = loadProjects ?? StorageService().loadProjects,
        _loadRecords = loadRecords ?? StorageService().loadGeoData,
        _trackingSessions = trackingSessions ??
            (() => TrackingSessionManager.instance.activeSessions),
        _outputDir = outputDir ?? getTemporaryDirectory,
        _now = now ?? DateTime.now;

  final Future<List<Project>> Function() _loadProjects;
  final Future<List<GeoData>> Function(String projectId) _loadRecords;
  final List<TrackingSession> Function() _trackingSessions;
  final Future<Directory> Function() _outputDir;
  final DateTime Function() _now;

  static const _tag = 'BACKUP';

  /// Nama aman untuk berkas/folder di dalam ZIP.
  static String safeName(String name) {
    final s = name.trim().replaceAll(RegExp(r'[^\w\-]+'), '_');
    final trimmed = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'untitled' : trimmed;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  Future<LocalBackupResult> create({
    String? username,
    void Function(String message)? onProgress,
  }) async {
    final started = _now();
    final stamp = '${started.year}${_two(started.month)}${_two(started.day)}_'
        '${_two(started.hour)}${_two(started.minute)}';
    final dir = await _outputDir();
    await dir.create(recursive: true);
    final path = p.join(
        dir.path, 'terestria_backup_${safeName(username ?? 'user')}_$stamp.zip');

    logInfo('Creating local backup → $path', tag: _tag);
    final encoder = ZipFileEncoder()..create(path);
    var closed = false;
    try {
      final projects = await _loadProjects();
      final photoSync = PhotoSyncService();
      var records = 0, unsynced = 0, photos = 0;
      final missing = <String>[];
      final projectSummaries = <Map<String, dynamic>>[];
      final usedFolders = <String>{};

      for (final project in projects) {
        onProgress?.call('Backing up "${project.name}"…');
        var folder = 'projects/${safeName(project.name)}';
        if (!usedFolders.add(folder)) {
          folder =
              '${folder}_${project.id.substring(0, math.min(8, project.id.length))}';
          usedFolders.add(folder);
        }

        List<GeoData> data;
        try {
          data = await _loadRecords(project.id);
        } catch (e, st) {
          // Satu project rusak tak menggagalkan seluruh cadangan.
          logError('Backup: could not read records of "${project.name}"',
              error: e, stack: st, tag: _tag);
          data = const [];
        }
        records += data.length;
        final projectUnsynced = data.where((d) => !d.isSynced).length;
        unsynced += projectUnsynced;

        _addText(encoder, '$folder/project.json',
            const JsonEncoder.withIndent('  ').convert(project.toJson()));
        _addText(
            encoder,
            '$folder/records.json',
            const JsonEncoder.withIndent('  ').convert(
                GeoExport.jsonSafe([for (final d in data) d.toJson()])));
        final geojson = GeoExport.geoJson(project, data);
        _addText(encoder, '$folder/${safeName(project.name)}.geojson',
            geojson.encode());

        var projectPhotos = 0;
        for (final d in data) {
          for (final photo in photoSync.pendingPhotoUploads(d.formData, project)) {
            final file = File(photo.localPath);
            if (!await file.exists()) {
              missing.add(photo.localPath);
              continue;
            }
            await _addPhoto(encoder, file,
                '$folder/photos/${d.id}/${p.basename(photo.localPath)}');
            projectPhotos++;
          }
        }
        photos += projectPhotos;
        projectSummaries.add({
          'id': project.id,
          'name': project.name,
          'folder': folder,
          'geometryType': project.geometryType.name,
          'projectSynced': project.isSynced,
          'records': data.length,
          'unsyncedRecords': projectUnsynced,
          'photos': projectPhotos,
          'recordsWithoutGeometry': geojson.skippedIds.length,
        });
      }

      // Sesi tracking yang belum disimpan jadi record.
      final sessions = _trackingSessions();
      if (sessions.isNotEmpty) {
        onProgress?.call('Backing up tracking sessions…');
        final features = <Map<String, dynamic>>[];
        final raw = <Map<String, dynamic>>[];
        for (final s in sessions) {
          raw.add({
            'projectId': s.projectId,
            'projectName': s.project.name,
            'state': s.state.name,
            'source': s.source.name,
            'startedAt': s.startedAt.toUtc().toIso8601String(),
            'points': [for (final pt in s.points) pt.toJson()],
          });
          final geometry =
              GeoExport.geometryFor(s.project.geometryType, s.points);
          if (geometry != null) {
            features.add({
              'type': 'Feature',
              'geometry': geometry,
              'properties': {
                'projectId': s.projectId,
                'projectName': s.project.name,
                'state': s.state.name,
                'startedAt': s.startedAt.toUtc().toIso8601String(),
                'pointCount': s.pointCount,
              },
            });
          }
        }
        _addText(encoder, 'tracking_sessions.json',
            const JsonEncoder.withIndent('  ').convert(GeoExport.jsonSafe(raw)));
        _addText(
            encoder,
            'tracking_sessions.geojson',
            const JsonEncoder.withIndent('  ').convert(
                {'type': 'FeatureCollection', 'features': features}));
      }

      final manifest = {
        'app': 'Terestria',
        'appVersion': ApiConfig.appVersion,
        'createdAt': started.toUtc().toIso8601String(),
        if (username != null) 'username': username,
        'projects': projectSummaries,
        'totals': {
          'projects': projects.length,
          'records': records,
          'unsyncedRecords': unsynced,
          'photos': photos,
          'missingPhotos': missing.length,
          'trackingSessions': sessions.length,
        },
        if (missing.isNotEmpty) 'missingPhotoPaths': missing,
      };
      _addText(encoder, 'manifest.json',
          const JsonEncoder.withIndent('  ').convert(manifest));
      _addText(encoder, 'README.txt', _readme(started, username));

      await encoder.close();
      closed = true;

      final file = File(path);
      final result = LocalBackupResult(
        file: file,
        projects: projects.length,
        records: records,
        unsyncedRecords: unsynced,
        photos: photos,
        missingPhotos: missing,
        trackingSessions: sessions.length,
        bytes: await file.length(),
      );
      logInfo('Backup created: $result', tag: _tag);
      if (missing.isNotEmpty) {
        logWarn('Backup: ${missing.length} photo file(s) no longer exist on '
            'the device', tag: _tag);
      }
      return result;
    } catch (e, st) {
      logError('Backup failed', error: e, stack: st, tag: _tag);
      if (!closed) {
        try {
          await encoder.close();
        } catch (_) {}
      }
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      rethrow;
    }
  }

  static void _addText(ZipFileEncoder encoder, String name, String content) =>
      encoder.addArchiveFile(ArchiveFile.string(name, content));

  static Future<void> _addPhoto(
      ZipFileEncoder encoder, File file, String name) async {
    final input = InputFileStream(file.path);
    try {
      final entry = ArchiveFile.stream(name, input)
        // JPEG sudah terkompresi — simpan apa adanya (hemat CPU & RAM).
        ..compression = CompressionType.none
        ..lastModTime =
            (await file.lastModified()).millisecondsSinceEpoch ~/ 1000;
      encoder.addArchiveFile(entry);
    } finally {
      await input.close();
    }
  }

  static String _readme(DateTime created, String? username) => '''
Terestria local backup
Created: ${created.toUtc().toIso8601String()}${username == null ? '' : '\nUser: $username'}

This archive was made on the phone before logging out. Logging out deletes
all data from the phone; this file keeps a copy of everything that was there.

Contents
  manifest.json                 Summary (counts per project, unsynced records)
  projects/<name>/project.json  Project definition and form fields
  projects/<name>/records.json  All records of the project (app format)
  projects/<name>/<name>.geojson  Records as GeoJSON (WGS84), opens in QGIS
  projects/<name>/photos/<record id>/  Photos that were not uploaded yet
  tracking_sessions.json/.geojson  Tracking sessions that were not saved yet

Send this file to your administrator so unsynced data can be recovered.
''';
}
