import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../utils/app_logger.dart';
import '../auth_service.dart';
import '../crashlytics_service.dart';
import '../database_service.dart';
import '../fcm_token_service.dart';
import '../firebase_messaging_service.dart';
import '../location_service_v2.dart';
import '../notification_topic_service.dart';
import '../offline_basemap_download_service.dart';
import '../routing_service.dart';
import '../tile_cache_sqlite_service.dart';
import '../tracking/tracking_persistence_coordinator.dart';
import '../tracking/tracking_session_manager.dart';

/// Kunci SharedPreferences milik PERANGKAT (bukan user) yang bertahan saat
/// logout: setelan tampilan & satuan, GPS, sumber lokasi & Emlid, identitas
/// perangkat, dan status yang sudah berlaku di level OS. Selain ini dihapus —
/// kunci baru di masa depan otomatis ikut terhapus (default-deny).
const Set<String> kResetKeepPrefKeys = {
  'app_settings',
  'gps_settings',
  'location_provider',
  'emlid_host',
  'emlid_port',
  'emlid_format',
  'device_id',
  'location_always_requested',
  'road_layer_visible',
  'has_migrated_to_sqlite',
};

/// Satu langkah reset; gagal → dicatat, langkah berikutnya tetap jalan.
class AppResetStep {
  final String name;
  final Future<void> Function() run;
  const AppResetStep(this.name, this.run);
}

class AppResetReport {
  final List<String> completed;
  final Map<String, Object> failed;
  const AppResetReport(this.completed, this.failed);
  bool get success => failed.isEmpty;
}

/// Reset app ke kondisi awal saat logout, agar user berikutnya tak melihat
/// data user sebelumnya. Urutan langkah penting (lihat [standardResetSteps]).
class AppResetService {
  final List<AppResetStep> steps;
  final Duration stepTimeout;

  AppResetService({
    List<AppResetStep>? steps,
    this.stepTimeout = const Duration(seconds: 20),
  }) : steps = steps ?? standardResetSteps();

  static const _tag = 'RESET';

  Future<AppResetReport> reset() async {
    final completed = <String>[];
    final failed = <String, Object>{};
    logInfo('Reset app dimulai (${steps.length} langkah)', tag: _tag);
    for (final step in steps) {
      try {
        await step.run().timeout(stepTimeout);
        completed.add(step.name);
      } catch (e, st) {
        failed[step.name] = e;
        logError('Langkah reset "${step.name}" gagal',
            tag: _tag, error: e, stack: st);
      }
    }
    logInfo(
        'Reset app selesai: ok=${completed.join(',')}'
        '${failed.isEmpty ? '' : ' gagal=${failed.keys.join(',')}'}',
        tag: _tag);
    await AppLogger.flush();
    return AppResetReport(completed, failed);
  }
}

/// Nama langkah standar, berurutan (dipakai test urutan).
List<String> get standardResetStepNames =>
    standardResetSteps().map((s) => s.name).toList();

/// Urutan wajib:
/// 1. tracking — sesi dibuang & koordinator persistensi menyinkronkannya
///    (engine melihat 0 sesi → berhenti);
/// 2. location — service background & log GPS dipastikan berhenti;
/// 3. downloads — unduhan basemap dihentikan;
/// 4. auth — logout + lepas topic scope FCM (butuh token & daftar topic di
///    prefs, jadi sebelum preferences);
/// 5. accounts — state user di singleton: topic notifikasi, token FCM
///    tercatat, auth token FCM, user Crashlytics, graf routing;
/// 6. databases — koneksi SQLite ditutup sebelum berkasnya dihapus;
/// 7. files — Documents & Temp dikosongkan; di folder yang juga dipakai
///    Firebase/plugin (databases, Application Support) hanya milik app;
/// 8. preferences — semua kunci dihapus kecuali [kResetKeepPrefKeys];
/// 9. memory — cache gambar (overlay PDF, foto) dikosongkan.
List<AppResetStep> standardResetSteps() => [
      AppResetStep('tracking', () async {
        TrackingSessionManager.instance.clearAll();
        await TrackingPersistenceCoordinator.active?.flushNow();
      }),
      AppResetStep('location', () async {
        final location = LocationServiceV2();
        await location.stopBackgroundTracking();
        await location.stopGpsLog();
      }),
      AppResetStep('downloads', () async {
        OfflineBasemapDownloadService().cancelDownload();
      }),
      AppResetStep('auth', () => AuthService()
          .logout(waitForCleanup: true)
          .timeout(const Duration(seconds: 12))),
      const AppResetStep('accounts', _resetAccountState),
      AppResetStep('databases', () async {
        await DatabaseService().close();
        await TileCacheSqliteService().closeAll();
      }),
      const AppResetStep('files', _wipeFiles),
      AppResetStep('preferences',
          () async => resetPreferences(await SharedPreferences.getInstance())),
      AppResetStep('memory', () async {
        PaintingBinding.instance.imageCache
          ..clear()
          ..clearLiveImages();
      }),
    ];

/// Tiap bagian dibungkus sendiri-sendiri: Firebase belum siap / offline tak
/// boleh menggagalkan reset bagian lain.
Future<void> _resetAccountState() async {
  final parts = <String, Future<void> Function()>{
    'token FCM tercatat': () async => FCMTokenService().forgetRegisteredToken(),
    'graf routing': () async => RoutingService().resetForLogout(),
    'auth token FCM': () async => FirebaseMessagingService().clearAuthToken(),
    'topic notifikasi': () => NotificationTopicService()
        .resetForLogout()
        .timeout(const Duration(seconds: 8)),
    'user Crashlytics': () => CrashlyticsService.instance.clearUser(),
  };
  await _runParts(parts);
}

/// Documents & Temp dikosongkan penuh. Folder databases & Application Support
/// juga dipakai Firebase/plugin → hanya milik app: `geoform.db*`, cache tile
/// (`MapTiles/`) dan cache graf GraphHopper (Android: `context.filesDir`).
Future<void> _wipeFiles() async {
  final removed = <String, int>{};
  await _runParts({
    'documents': () async => removed['documents'] =
        await wipeDirectory(await getApplicationDocumentsDirectory()),
    'temp': () async =>
        removed['temp'] = await wipeDirectory(await getTemporaryDirectory()),
    'databases': () async => removed['databases'] = await wipeDirectory(
        Directory(await getDatabasesPath()),
        only: (name) => name.startsWith(DatabaseService.databaseName)),
    'support': () async => removed['support'] = await wipeDirectory(
        await getApplicationSupportDirectory(),
        only: (name) =>
            name == 'MapTiles' || name.startsWith('gh-graph-cache')),
  });
  logInfo('Berkas dihapus: $removed', tag: 'RESET');
}

/// Jalankan [parts] berurutan; yang gagal dicatat lalu dilewati. Bila ada
/// yang gagal, lempar di akhir agar langkahnya tercatat gagal di laporan.
Future<void> _runParts(Map<String, Future<void> Function()> parts) async {
  final failed = <String>[];
  for (final e in parts.entries) {
    try {
      await e.value();
    } catch (err) {
      failed.add(e.key);
      logWarn('Reset ${e.key} gagal: $err', tag: 'RESET');
    }
  }
  if (failed.isNotEmpty) throw StateError('gagal: ${failed.join(', ')}');
}

/// Hapus isi [dir] (bukan folder-nya). [only] membatasi ke nama entri
/// langsung yang cocok — untuk folder yang juga dipakai Firebase/plugin.
/// Entri yang gagal dihapus dicatat lalu dilewati. Mengembalikan jumlah entri
/// yang terhapus.
Future<int> wipeDirectory(Directory dir,
    {bool Function(String name)? only}) async {
  if (!await dir.exists()) return 0;
  var removed = 0;
  await for (final entity in dir.list(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (only != null && !only(name)) continue;
    try {
      await entity.delete(recursive: true);
      removed++;
    } catch (e) {
      logWarn('Gagal menghapus ${entity.path}: $e', tag: 'RESET');
    }
  }
  return removed;
}

/// Kosongkan SharedPreferences lalu pulihkan kunci [keep] dengan tipe aslinya.
Future<void> resetPreferences(SharedPreferences prefs,
    {Set<String> keep = kResetKeepPrefKeys}) async {
  final saved = <String, Object>{
    for (final k in keep)
      if (prefs.get(k) != null) k: prefs.get(k)!,
  };
  await prefs.clear();
  for (final e in saved.entries) {
    final v = e.value;
    if (v is String) {
      await prefs.setString(e.key, v);
    } else if (v is bool) {
      await prefs.setBool(e.key, v);
    } else if (v is int) {
      await prefs.setInt(e.key, v);
    } else if (v is double) {
      await prefs.setDouble(e.key, v);
    } else if (v is List) {
      await prefs.setStringList(e.key, v.cast<String>());
    }
  }
}
