import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../utils/app_logger.dart';
import '../auth_service.dart';
import '../database_service.dart';
import '../location_service_v2.dart';
import '../offline_basemap_download_service.dart';
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
/// 1. tracking — sesi dibuang, service & feed GPS berhenti (tak menulis lagi);
/// 2. downloads — unduhan basemap dihentikan;
/// 3. auth — logout + lepas topic FCM (butuh token & daftar topic di prefs);
/// 4. databases — koneksi SQLite ditutup sebelum berkasnya dihapus;
/// 5. files — Documents & Temp dikosongkan; di folder yang juga dipakai
///    Firebase/plugin (databases, Application Support) hanya milik app;
/// 6. preferences — semua kunci dihapus kecuali [kResetKeepPrefKeys];
/// 7. memory — cache gambar (overlay PDF, foto) dikosongkan.
List<AppResetStep> standardResetSteps() => [
      const AppResetStep('tracking', _stopTracking),
      AppResetStep('downloads', () async {
        OfflineBasemapDownloadService().cancelDownload();
      }),
      AppResetStep('auth', () => AuthService()
          .logout(waitForCleanup: true)
          .timeout(const Duration(seconds: 12))),
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

Future<void> _stopTracking() async {
  // Buang sesi (engine melihat 0 sesi → hentikan service/feed), lalu pastikan
  // berhenti & koordinator persistensi menyinkronkan state kosongnya.
  TrackingSessionManager.instance.clearAll();
  final location = LocationServiceV2();
  await location.stopBackgroundTracking();
  await location.stopGpsLog();
  await TrackingPersistenceCoordinator.active?.flushNow();
}

Future<void> _wipeFiles() async {
  final removed = <String, int>{
    'documents': await wipeDirectory(await getApplicationDocumentsDirectory()),
    'temp': await wipeDirectory(await getTemporaryDirectory()),
    'databases': await wipeDirectory(Directory(await getDatabasesPath()),
        only: (name) => name.startsWith(DatabaseService.databaseName)),
    'support': await wipeDirectory(await getApplicationSupportDirectory(),
        only: (name) => name == 'MapTiles'),
  };
  logInfo('Berkas dihapus: $removed', tag: 'RESET');
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
