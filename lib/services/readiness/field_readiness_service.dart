import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
// Prefix: extension `.status` ikut terimpor tanpa bentrok nama geolocator.
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../models/basemap_model.dart';
import '../../models/geo_data_model.dart';
import '../../utils/app_logger.dart';
import '../basemap_service.dart';
import '../device_health_service.dart';
import '../location_service_v2.dart';
import '../photo_sync_service.dart';
import '../storage_service.dart';
import '../tile_cache_sqlite_service.dart';
import '../tracking/tracking_session_manager.dart';
import 'field_readiness.dart';

/// Mengumpulkan [ReadinessInputs] dari perangkat. Setiap langkah berdiri
/// sendiri: bila satu gagal, dicatat di log dan butir itu "tak diketahui" —
/// checklist tetap tampil.
class FieldReadinessService {
  static const _tag = 'READY';

  /// Batas waktu mencoba fix GPS saat checklist dibuka.
  static const gpsTimeout = Duration(seconds: 20);

  Future<T?> _safe<T>(String step, Future<T> Function() f,
      {Duration timeout = const Duration(seconds: 8)}) async {
    try {
      return await f().timeout(timeout);
    } catch (e, st) {
      logWarn('Readiness check "$step" failed', tag: _tag, error: e, stack: st);
      return null;
    }
  }

  static LocationAccess accessFrom(LocationPermission? p) => switch (p) {
        LocationPermission.always => LocationAccess.always,
        LocationPermission.whileInUse => LocationAccess.whileInUse,
        LocationPermission.denied => LocationAccess.denied,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        _ => LocationAccess.unknown,
      };

  /// [testGps] false = lewati percobaan fix (cek cepat sebelum Start).
  /// [previousFix] dipakai bila fix baru tak didapat.
  Future<ReadinessInputs> collect({
    bool testGps = true,
    GeoPoint? previousFix,
  }) async {
    final location = LocationServiceV2();
    final health = DeviceHealthService();

    final serviceOn = await _safe(
        'location service', Geolocator.isLocationServiceEnabled);
    final permission =
        await _safe('location permission', Geolocator.checkPermission);
    final access = accessFrom(permission);
    final notifications = Platform.isAndroid
        ? await _safe('notifications',
            () async => (await ph.Permission.notification.status).isGranted)
        : null;
    final battery = await _safe(
        'battery optimization', health.isIgnoringBatteryOptimizations);
    final manufacturer = await _safe('manufacturer', health.manufacturer);
    final free = await _safe('storage', health.freeDiskBytes);

    GeoPoint? fix = previousFix;
    final canFix = serviceOn != false &&
        (access == LocationAccess.always ||
            access == LocationAccess.whileInUse);
    if (testGps && canFix) {
      final fresh = await _safe('gps fix', location.getCurrentLocation,
          timeout: gpsTimeout);
      if (fresh != null) fix = fresh;
    }

    final usingEmlid = location.currentProvider == LocationProvider.emlid;

    // Peta offline di posisi saat ini.
    var offline = OfflineCoverage.unknown;
    String? basemapName;
    final basemap =
        await _safe('selected basemap', BasemapService().getSelectedBasemap);
    if (basemap != null) {
      basemapName = basemap.name;
      offline = fix == null
          ? OfflineCoverage.noLocation
          : (await _safe('offline coverage',
                  () => offlineCoverageAt(basemap, fix!))) ??
              OfflineCoverage.unknown;
    }

    // Data yang belum tersinkron.
    var unsynced = 0, photos = 0;
    await _safe('pending sync', () async {
      final storage = StorageService();
      final data = await storage.getUnsyncedGeoData();
      unsynced = await storage.getUnsyncedGeoDataCount();
      if (data.length > unsynced) unsynced = data.length;
      final projects = {for (final p in await storage.loadProjects()) p.id: p};
      final photoSync = PhotoSyncService();
      for (final g in data) {
        final project = projects[g.projectId];
        if (project == null) continue;
        photos += photoSync.pendingPhotoUploads(g.formData, project).length;
      }
      return true;
    }, timeout: const Duration(seconds: 15));

    final unsaved = TrackingSessionManager.instance.activeSessions
        .where((s) => s.pendingSave)
        .length;

    final inputs = ReadinessInputs(
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
      now: DateTime.now(),
      locationServiceOn: serviceOn,
      locationAccess: access,
      notificationsAllowed: notifications,
      ignoringBatteryOptimizations: battery,
      manufacturer: manufacturer,
      freeBytes: free,
      lastFix: fix,
      gpsTested: testGps && canFix,
      usingEmlid: usingEmlid,
      emlid: usingEmlid ? location.emlidStatus.value : null,
      lastEmlidData: usingEmlid ? location.lastEmlidDataTime : null,
      basemapName: basemapName,
      offline: offline,
      unsyncedRecords: unsynced,
      pendingPhotos: photos,
      unsavedSessions: unsaved,
    );
    final counts = readinessCounts(evaluateReadiness(inputs));
    logInfo(
        'Readiness: ${counts.problems} problem(s), ${counts.warnings} '
        'warning(s); access=${access.name} gps=${serviceOn ?? '?'} '
        'battery=${battery ?? '?'} free=${free == null ? '?' : formatBytes(free)} '
        'fix=${fix == null ? 'none' : '±${fix.accuracy?.toStringAsFixed(1)}m'} '
        'offline=${offline.name} unsynced=$unsynced photos=$photos',
        tag: _tag);
    return inputs;
  }

  /// Apakah basemap aktif tersedia offline di [at]? PDF: cek batas peta;
  /// online: cari tile tersimpan di zoom lapangan (17 → 14).
  static Future<OfflineCoverage> offlineCoverageAt(
      Basemap basemap, GeoPoint at) async {
    if (basemap.type == BasemapType.pdf) {
      final minLat = basemap.pdfMinLat, maxLat = basemap.pdfMaxLat;
      final minLon = basemap.pdfMinLon, maxLon = basemap.pdfMaxLon;
      if (minLat == null || maxLat == null || minLon == null || maxLon == null) {
        return OfflineCoverage.unknown;
      }
      final inside = at.latitude >= minLat &&
          at.latitude <= maxLat &&
          at.longitude >= minLon &&
          at.longitude <= maxLon;
      return inside ? OfflineCoverage.pdfCovers : OfflineCoverage.pdfOutside;
    }
    final cache = TileCacheSqliteService();
    for (final z in const [17, 16, 15, 14]) {
      if (z < basemap.minZoom || z > basemap.maxZoom) continue;
      final t = tileForLatLon(at.latitude, at.longitude, z);
      final tile =
          await cache.getTile(basemapId: basemap.id, z: z, x: t.x, y: t.y);
      if (tile != null) return OfflineCoverage.available;
    }
    return OfflineCoverage.missing;
  }
}
