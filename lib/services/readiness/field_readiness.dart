import 'dart:math' as math;

import '../../models/geo_data_model.dart';
import '../device_health_service.dart';
import '../location_service_v2.dart' show EmlidStatus;

/// Tingkat satu butir checklist "Ready for the field".
enum ReadinessLevel { ok, warning, problem, info }

/// Aksi perbaikan yang ditawarkan satu butir (dijalankan oleh layar).
enum ReadinessFix {
  none,
  requestLocation,
  openAppSettings,
  openLocationSettings,
  openBatterySettings,
  openBasemaps,
  openLocationProvider,
  syncNow,
  retestGps,
}

/// Akses lokasi, dinormalkan dari geolocator/permission_handler.
enum LocationAccess { always, whileInUse, denied, deniedForever, unknown }

/// Ketersediaan peta offline di posisi user.
enum OfflineCoverage {
  /// Tile basemap aktif tersimpan di sekitar posisi.
  available,

  /// Basemap online, tile di posisi ini belum tersimpan.
  missing,

  /// Basemap PDF/GeoPDF mencakup posisi.
  pdfCovers,

  /// Basemap PDF tak mencakup posisi.
  pdfOutside,

  /// Posisi belum diketahui → tak bisa dicek.
  noLocation,
  unknown,
}

class ReadinessItem {
  final String id;
  final String title;
  final String detail;
  final ReadinessLevel level;
  final ReadinessFix fix;
  final String? fixLabel;

  /// Panduan tambahan (mis. langkah per merek HP).
  final String? help;

  const ReadinessItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.level,
    this.fix = ReadinessFix.none,
    this.fixLabel,
    this.help,
  });
}

/// Semua masukan checklist — dikumpulkan [FieldReadinessService], dievaluasi
/// murni oleh [evaluateReadiness] (teruji tanpa plugin).
class ReadinessInputs {
  final bool isAndroid;
  final bool isIOS;
  final DateTime now;
  final bool? locationServiceOn;
  final LocationAccess locationAccess;
  final bool? notificationsAllowed;
  final bool? ignoringBatteryOptimizations;
  final String? manufacturer;
  final int? freeBytes;

  /// Fix terakhir; [gpsTested] true bila percobaan fix sudah dilakukan.
  final GeoPoint? lastFix;
  final bool gpsTested;

  final bool usingEmlid;
  final EmlidStatus? emlid;
  final DateTime? lastEmlidData;

  final String? basemapName;
  final OfflineCoverage offline;

  final int unsyncedRecords;
  final int pendingPhotos;
  final int unsavedSessions;

  const ReadinessInputs({
    required this.isAndroid,
    required this.isIOS,
    required this.now,
    this.locationServiceOn,
    this.locationAccess = LocationAccess.unknown,
    this.notificationsAllowed,
    this.ignoringBatteryOptimizations,
    this.manufacturer,
    this.freeBytes,
    this.lastFix,
    this.gpsTested = false,
    this.usingEmlid = false,
    this.emlid,
    this.lastEmlidData,
    this.basemapName,
    this.offline = OfflineCoverage.unknown,
    this.unsyncedRecords = 0,
    this.pendingPhotos = 0,
    this.unsavedSessions = 0,
  });
}

/// Akurasi fix HP yang dianggap siap (m) — di atasnya kuning.
const double readinessGoodAccuracyM = 10;

/// Akurasi di atas ini dianggap lemah.
const double readinessWeakAccuracyM = 30;

/// Fix lebih tua dari ini dianggap basi.
const Duration readinessStaleFix = Duration(minutes: 2);

String _ago(Duration d) {
  if (d.inSeconds < 60) return '${math.max(0, d.inSeconds)} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}

String _plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

/// Checklist berurutan: yang paling menentukan (izin, GPS) di atas.
List<ReadinessItem> evaluateReadiness(ReadinessInputs i) {
  final items = <ReadinessItem>[];
  final permissionOk = i.locationAccess == LocationAccess.always ||
      i.locationAccess == LocationAccess.whileInUse;

  // 1. Izin lokasi
  switch (i.locationAccess) {
    case LocationAccess.always:
      items.add(const ReadinessItem(
        id: 'location_permission',
        title: 'Location access',
        detail: 'Allowed all the time',
        level: ReadinessLevel.ok,
      ));
    case LocationAccess.whileInUse:
      items.add(i.isIOS
          ? const ReadinessItem(
              id: 'location_permission',
              title: 'Location access',
              detail: 'Only "While Using the App". iOS may pause tracking '
                  'while Terestria is in the background — choose "Always".',
              level: ReadinessLevel.warning,
              fix: ReadinessFix.openAppSettings,
              fixLabel: 'Open settings',
            )
          : const ReadinessItem(
              id: 'location_permission',
              title: 'Location access',
              detail: 'Allowed while using the app. Tracking keeps running '
                  'through the tracking notification.',
              level: ReadinessLevel.ok,
            ));
    case LocationAccess.denied:
      items.add(const ReadinessItem(
        id: 'location_permission',
        title: 'Location access',
        detail: 'Terestria is not allowed to use your location.',
        level: ReadinessLevel.problem,
        fix: ReadinessFix.requestLocation,
        fixLabel: 'Allow',
      ));
    case LocationAccess.deniedForever:
      items.add(const ReadinessItem(
        id: 'location_permission',
        title: 'Location access',
        detail: 'Location was denied permanently. Allow it in the app '
            'settings (Permissions → Location).',
        level: ReadinessLevel.problem,
        fix: ReadinessFix.openAppSettings,
        fixLabel: 'Open settings',
      ));
    case LocationAccess.unknown:
      items.add(const ReadinessItem(
        id: 'location_permission',
        title: 'Location access',
        detail: 'Could not check the location permission.',
        level: ReadinessLevel.info,
        fix: ReadinessFix.openAppSettings,
        fixLabel: 'Open settings',
      ));
  }

  // 2. Layanan lokasi (GPS) menyala
  if (i.locationServiceOn == false) {
    items.add(const ReadinessItem(
      id: 'location_service',
      title: 'Location (GPS)',
      detail: 'Location is turned off on this phone.',
      level: ReadinessLevel.problem,
      fix: ReadinessFix.openLocationSettings,
      fixLabel: 'Turn on',
    ));
  } else if (i.locationServiceOn == true) {
    items.add(const ReadinessItem(
      id: 'location_service',
      title: 'Location (GPS)',
      detail: 'Location is on',
      level: ReadinessLevel.ok,
    ));
  }

  // 3. Fix GPS (akurasi & umur)
  if (permissionOk && i.locationServiceOn != false) {
    final fix = i.lastFix;
    if (fix == null) {
      items.add(ReadinessItem(
        id: 'gps_fix',
        title: 'GPS signal',
        detail: i.gpsTested
            ? 'No GPS fix yet. Go outdoors with a clear view of the sky and '
                'wait a minute, then test again.'
            : 'Checking GPS…',
        level: i.gpsTested ? ReadinessLevel.warning : ReadinessLevel.info,
        fix: i.gpsTested ? ReadinessFix.retestGps : ReadinessFix.none,
        fixLabel: i.gpsTested ? 'Test again' : null,
      ));
    } else {
      final age = i.now.difference(fix.timestamp);
      final acc = fix.accuracy;
      final accText = acc == null ? 'accuracy unknown' : '±${acc.toStringAsFixed(acc < 10 ? 1 : 0)} m';
      final quality = fix.fixQuality == null ? '' : ' · ${fix.fixQuality!.toUpperCase()}';
      final stale = age > readinessStaleFix;
      final weak = acc == null || acc > readinessWeakAccuracyM;
      final fair = acc != null && acc > readinessGoodAccuracyM;
      items.add(ReadinessItem(
        id: 'gps_fix',
        title: 'GPS signal',
        detail: '$accText$quality · ${_ago(age)}'
            '${stale ? '. This fix is old — test again outdoors.' : weak ? '. Signal is weak — move to an open area.' : fair ? '. Usable; accuracy improves after a minute outdoors.' : ''}',
        level: (stale || weak || fair)
            ? ReadinessLevel.warning
            : ReadinessLevel.ok,
        fix: ReadinessFix.retestGps,
        fixLabel: 'Test again',
      ));
    }
  }

  // 4. Receiver RTK (Emlid) bila dipakai
  if (i.usingEmlid) {
    final e = i.emlid ?? const EmlidStatus();
    final sinceData =
        i.lastEmlidData == null ? null : i.now.difference(i.lastEmlidData!);
    if (e.reconnecting) {
      items.add(ReadinessItem(
        id: 'emlid',
        title: 'RTK receiver (Emlid)',
        detail: 'Connection lost — reconnecting (attempt ${e.reconnectAttempt}).',
        level: ReadinessLevel.warning,
        fix: ReadinessFix.openLocationProvider,
        fixLabel: 'Open',
      ));
    } else if (!e.connected) {
      items.add(const ReadinessItem(
        id: 'emlid',
        title: 'RTK receiver (Emlid)',
        detail: 'Not connected. Connect to the receiver\'s Wi-Fi/hotspot, '
            'then connect in Location provider.',
        level: ReadinessLevel.problem,
        fix: ReadinessFix.openLocationProvider,
        fixLabel: 'Connect',
      ));
    } else if (sinceData != null && sinceData > const Duration(seconds: 10)) {
      items.add(ReadinessItem(
        id: 'emlid',
        title: 'RTK receiver (Emlid)',
        detail: 'Connected, but no data for ${sinceData.inSeconds} s. Check '
            'the receiver\'s position output.',
        level: ReadinessLevel.warning,
        fix: ReadinessFix.openLocationProvider,
        fixLabel: 'Open',
      ));
    } else if (e.belowRequirement) {
      items.add(ReadinessItem(
        id: 'emlid',
        title: 'RTK receiver (Emlid)',
        detail: 'Connected · ${(e.lastQuality ?? '?').toUpperCase()} '
            '(required ${e.requiredQuality.toUpperCase()}). Points are NOT '
            'recorded until the required quality is reached.',
        level: ReadinessLevel.warning,
      ));
    } else {
      items.add(ReadinessItem(
        id: 'emlid',
        title: 'RTK receiver (Emlid)',
        detail: 'Connected${e.lastQuality == null ? '' : ' · ${e.lastQuality!.toUpperCase()}'}',
        level: ReadinessLevel.ok,
      ));
    }
  }

  // 5. Optimasi baterai (Android)
  if (i.isAndroid) {
    if (i.ignoringBatteryOptimizations == true) {
      items.add(const ReadinessItem(
        id: 'battery',
        title: 'Battery optimization',
        detail: 'Off for Terestria — tracking can run with the screen off.',
        level: ReadinessLevel.ok,
      ));
    } else {
      items.add(ReadinessItem(
        id: 'battery',
        title: 'Battery optimization',
        detail: i.ignoringBatteryOptimizations == false
            ? 'On for Terestria. The phone may stop tracking when the screen '
                'is off. Set Terestria to "Unrestricted" / "Don\'t optimize".'
            : 'Could not check. Make sure Terestria is not battery-optimized.',
        level: i.ignoringBatteryOptimizations == false
            ? ReadinessLevel.warning
            : ReadinessLevel.info,
        fix: ReadinessFix.openBatterySettings,
        fixLabel: 'Open settings',
        help: batteryGuidanceFor(i.manufacturer),
      ));
    }
  }

  // 6. Notifikasi (Android 13+: notifikasi tracking)
  if (i.isAndroid && i.notificationsAllowed == false) {
    items.add(const ReadinessItem(
      id: 'notifications',
      title: 'Notifications',
      detail: 'Blocked. The tracking notification is hidden, so you cannot '
          'see that tracking is running.',
      level: ReadinessLevel.warning,
      fix: ReadinessFix.openAppSettings,
      fixLabel: 'Open settings',
    ));
  }

  // 7. Penyimpanan
  final storage = storageLevelFor(i.freeBytes);
  switch (storage) {
    case StorageLevel.ok:
      items.add(ReadinessItem(
        id: 'storage',
        title: 'Storage',
        detail: '${formatBytes(i.freeBytes!)} free',
        level: ReadinessLevel.ok,
      ));
    case StorageLevel.low:
      items.add(ReadinessItem(
        id: 'storage',
        title: 'Storage',
        detail: 'Only ${formatBytes(i.freeBytes!)} free. Photos and offline '
            'maps may fail — free up space.',
        level: ReadinessLevel.warning,
      ));
    case StorageLevel.critical:
      items.add(ReadinessItem(
        id: 'storage',
        title: 'Storage',
        detail: 'Almost full (${formatBytes(i.freeBytes!)} free). Data may '
            'not be saved — free up space before going out.',
        level: ReadinessLevel.problem,
      ));
    case StorageLevel.unknown:
      break;
  }

  // 8. Peta offline di posisi saat ini
  final map = i.basemapName == null ? 'The map' : '"${i.basemapName}"';
  switch (i.offline) {
    case OfflineCoverage.available:
      items.add(ReadinessItem(
        id: 'offline_map',
        title: 'Offline map',
        detail: '$map is saved for your current area.',
        level: ReadinessLevel.ok,
      ));
    case OfflineCoverage.missing:
      items.add(ReadinessItem(
        id: 'offline_map',
        title: 'Offline map',
        detail: '$map is not saved for your current area. Without internet '
            'the map will be blank — download the area first.',
        level: ReadinessLevel.warning,
        fix: ReadinessFix.openBasemaps,
        fixLabel: 'Basemaps',
      ));
    case OfflineCoverage.pdfCovers:
      items.add(ReadinessItem(
        id: 'offline_map',
        title: 'Offline map',
        detail: '$map (PDF) covers your current location.',
        level: ReadinessLevel.ok,
      ));
    case OfflineCoverage.pdfOutside:
      items.add(ReadinessItem(
        id: 'offline_map',
        title: 'Offline map',
        detail: 'You are outside $map (PDF).',
        level: ReadinessLevel.warning,
        fix: ReadinessFix.openBasemaps,
        fixLabel: 'Basemaps',
      ));
    case OfflineCoverage.noLocation:
      items.add(const ReadinessItem(
        id: 'offline_map',
        title: 'Offline map',
        detail: 'Get a GPS fix to check whether the map is saved for this '
            'area.',
        level: ReadinessLevel.info,
      ));
    case OfflineCoverage.unknown:
      break;
  }

  // 9. Data yang hanya ada di HP
  if (i.unsyncedRecords > 0 || i.pendingPhotos > 0) {
    final parts = [
      if (i.unsyncedRecords > 0) _plural(i.unsyncedRecords, 'record'),
      if (i.pendingPhotos > 0) _plural(i.pendingPhotos, 'photo'),
    ];
    items.add(ReadinessItem(
      id: 'pending_sync',
      title: 'Unsynced data',
      detail: '${parts.join(' and ')} only on this phone. Sync while you '
          'still have a connection.',
      level: ReadinessLevel.warning,
      fix: ReadinessFix.syncNow,
      fixLabel: 'Sync now',
    ));
  } else {
    items.add(const ReadinessItem(
      id: 'pending_sync',
      title: 'Unsynced data',
      detail: 'Everything is synced',
      level: ReadinessLevel.ok,
    ));
  }
  if (i.unsavedSessions > 0) {
    items.add(ReadinessItem(
      id: 'unsaved_sessions',
      title: 'Unsaved tracks',
      detail: '${_plural(i.unsavedSessions, 'tracking session')} not saved '
          'as records yet. Save or discard them in the Active Tracking panel.',
      level: ReadinessLevel.warning,
    ));
  }

  // 10. Kebiasaan yang menghentikan tracking
  items.add(ReadinessItem(
    id: 'keep_app',
    title: 'While tracking',
    detail: i.isAndroid
        ? 'Leave Terestria with the Home button. Swiping it away from Recent '
            'apps stops tracking.'
        : 'Leave Terestria with the Home gesture. Closing it from the app '
            'switcher stops tracking.',
    level: ReadinessLevel.info,
  ));

  return items;
}

/// Ringkasan: jumlah butir bermasalah/peringatan.
({int problems, int warnings}) readinessCounts(List<ReadinessItem> items) => (
      problems: items.where((i) => i.level == ReadinessLevel.problem).length,
      warnings: items.where((i) => i.level == ReadinessLevel.warning).length,
    );

/// Hasil uji GPS lengkap terakhir (layar checklist): butir "GPS signal" saat
/// itu dan fix-nya. Beranda tidak menguji GPS, jadi memakai hasil ini.
class GpsTestResult {
  final DateTime at;
  final ReadinessItem item;
  final GeoPoint? fix;

  const GpsTestResult({required this.at, required this.item, this.fix});
}

/// Hasil uji GPS dari [inputs], atau null bila GPS tidak diuji.
GpsTestResult? gpsTestResultOf(ReadinessInputs inputs) {
  if (!inputs.gpsTested) return null;
  final item =
      evaluateReadiness(inputs).where((i) => i.id == 'gps_fix').firstOrNull;
  if (item == null) return null;
  return GpsTestResult(at: inputs.now, item: item, fix: inputs.lastFix);
}

/// Batas umur hasil yang dipakai ulang di beranda: uji GPS terakhir dan posisi
/// untuk cek peta offline. Lebih tua → dianggap belum dicek.
const Duration readinessHomeMaxAge = Duration(minutes: 30);

/// Fix terbaru di [fixes] yang umurnya ≤ [maxAge], atau null.
GeoPoint? freshestFix(
    Iterable<GeoPoint?> fixes, DateTime now, Duration maxAge) {
  GeoPoint? best;
  for (final f in fixes) {
    if (f == null || now.difference(f.timestamp) > maxAge) continue;
    if (best == null || f.timestamp.isAfter(best.timestamp)) best = f;
  }
  return best;
}

/// Ringkasan kartu kesiapan di beranda.
class HomeReadinessSummary {
  /// [ReadinessLevel.ok], [ReadinessLevel.warning], atau
  /// [ReadinessLevel.problem].
  final ReadinessLevel level;
  final String title;
  final String subtitle;

  /// Sinyal GPS sudah diuji (uji lengkap yang masih berlaku).
  final bool gpsTested;

  const HomeReadinessSummary({
    required this.level,
    required this.title,
    required this.subtitle,
    required this.gpsTested,
  });
}

/// Ringkasan beranda dari cek cepat [quick] (tanpa uji GPS) dan uji GPS
/// lengkap terakhir [lastGpsTest] bila masih berlaku ([readinessHomeMaxAge]).
/// "Ready for the field" hanya bila GPS sudah diuji dan semuanya lolos;
/// tanpa uji GPS yang berlaku, judul hijau = "No problems found". Data belum
/// sync tidak dihitung (punya kartu sendiri).
HomeReadinessSummary homeReadinessSummary(ReadinessInputs quick,
    {GpsTestResult? lastGpsTest}) {
  var items = evaluateReadiness(quick);
  final valid = lastGpsTest != null &&
      quick.now.difference(lastGpsTest.at) <= readinessHomeMaxAge;
  // Butir GPS hanya ada bila izin lokasi & GPS menyala.
  final gpsTested = valid && items.any((i) => i.id == 'gps_fix');
  if (gpsTested) {
    items = [for (final i in items) i.id == 'gps_fix' ? lastGpsTest.item : i];
  }
  final attention = items
      .where((i) =>
          i.level == ReadinessLevel.problem ||
          i.level == ReadinessLevel.warning)
      .where((i) => i.id != 'pending_sync')
      .toList();
  final problems =
      attention.where((i) => i.level == ReadinessLevel.problem).length;
  final warnings = attention.length - problems;
  final names = attention.take(3).map((i) => i.title).join(' · ');
  if (problems > 0) {
    return HomeReadinessSummary(
      level: ReadinessLevel.problem,
      title: '$problems problem${problems == 1 ? '' : 's'} before the field',
      subtitle: names,
      gpsTested: gpsTested,
    );
  }
  if (warnings > 0) {
    return HomeReadinessSummary(
      level: ReadinessLevel.warning,
      title: '$warnings ${warnings == 1 ? 'item needs' : 'items need'} '
          'attention',
      subtitle: names,
      gpsTested: gpsTested,
    );
  }
  return gpsTested
      ? const HomeReadinessSummary(
          level: ReadinessLevel.ok,
          title: 'Ready for the field',
          subtitle: 'Permissions, GPS, battery and storage look good',
          gpsTested: true,
        )
      : const HomeReadinessSummary(
          level: ReadinessLevel.ok,
          title: 'No problems found',
          subtitle: 'Tap to test GPS signal',
          gpsTested: false,
        );
}

/// Tile slippy-map (x, y) untuk [lat]/[lon] pada zoom [z].
({int x, int y}) tileForLatLon(double lat, double lon, int z) {
  final n = 1 << z;
  final clampedLat = lat.clamp(-85.05112878, 85.05112878);
  final latRad = clampedLat * math.pi / 180;
  final x = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
  final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
          2 *
          n)
      .floor()
      .clamp(0, n - 1);
  return (x: x, y: y);
}
