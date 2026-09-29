import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/route_result.dart';
import 'api_service.dart';
import 'routing_dart/engine.dart';
import 'tile_cache_sqlite_service.dart';

import '../utils/app_logger.dart';
/// Gate ketersediaan routing lintas-platform: Android selalu (GraphHopper); iOS
/// bila mesin Dart offline diaktifkan. Dipakai RoutingService & RoutingDataManager.
bool routingAvailable({
  required bool isAndroid,
  required bool isIos,
  required bool iosEngineEnabled,
}) =>
    isAndroid || (isIos && iosEngineEnabled);

/// Company yang bisa diunduh data jalannya (dari /mobile/roads/companies/).
class DownloadableCompany {
  final int id;
  final String name;
  final int roadCount;
  const DownloadableCompany({required this.id, required this.name, required this.roadCount});

  bool get hasData => roadCount > 0;
}

/// Road data sebuah company yang sudah tersimpan lokal (bisa dipakai offline).
class DownloadedRoad {
  final int id;
  final String name;
  final String path;
  const DownloadedRoad({required this.id, required this.name, required this.path});
}

/// Hasil download+prepare road data.
enum RoadPrepareStatus { ready, empty, error }

class RoadPrepareResult {
  final RoadPrepareStatus status;
  final String message;
  const RoadPrepareResult(this.status, this.message);
}

/// Parse body /mobile/roads/companies/ → daftar company (buang yang code kosong).
List<DownloadableCompany> parseCompanies(String body) {
  try {
    final data = jsonDecode(body);
    final list = (data is Map && data['companies'] is List)
        ? data['companies'] as List
        : const [];
    return list
        .map((e) => DownloadableCompany(
              id: (e['id'] as num?)?.toInt() ?? 0,
              name: e['name']?.toString() ?? '',
              roadCount: (e['road_count'] as num?)?.toInt() ?? 0,
            ))
        .where((c) => c.id > 0)
        .toList();
  } catch (_) {
    return [];
  }
}

/// Routing service: GraphHopper on Android (MethodChannel), pure-Dart engine
/// ([DartRoutingEngine]) on iOS. Kontrak I/O sama di kedua platform.
///
/// Also provides pure-Dart navigation algorithms ported from the analyzed APK:
///   - snapToRoute()     ← RouteSnapper.java
///   - detectOffRoute()  ← NavigationHelper.java
///   - isRouteCompleted()
///   - detectUTurns()
///   - updateInstruction()
class RoutingService {
  static final RoutingService _instance = RoutingService._internal();
  factory RoutingService() => _instance;
  RoutingService._internal();

  static const _channel    = MethodChannel('com.terestria/routing');
  static const _prefOsmKey = 'routing_osm_file_path';
  static const _prefDownloadedIndex = 'routing_downloaded_roads'; // JSON [{id,name}]

  /// Aktifkan mesin routing Dart di iOS. Set false → iOS kembali graceful
  /// (dialog "belum tersedia"), tanpa menyentuh jalur Android.
  static const bool iosEngineEnabled = true;

  /// Mesin routing offline pure-Dart — HANYA dipakai di iOS. Android tetap
  /// lewat MethodChannel/GraphHopper (tak tersentuh).
  final DartRoutingEngine _iosEngine = DartRoutingEngine();

  // Constants from APK
  static const double _offRouteDist     = 40.0;  // meters — NavigationHelper
  static const double _gpsStableAccuracy = 10.0; // meters — isGPSStable()
  static const double _arrivedDist      = 15.0;  // meters — arrival threshold
  static const double _arrivedBearing   = 10.0;  // degrees
  static const double _uTurnBearing     = 150.0; // degrees — detectUTurns
  static const double _uTurnDist        = 50.0;  // meters  — sliding window span
  static const double _uTurnSpeed       = 5.0;   // km/h    — max speed for U-turn

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool get _isAndroid => Platform.isAndroid;

  /// Routing didukung di perangkat ini? Android selalu; iOS bila mesin Dart aktif.
  bool get _routingSupported => routingAvailable(
        isAndroid: Platform.isAndroid,
        isIos: Platform.isIOS,
        iosEngineEnabled: iosEngineEnabled,
      );

  // ─────────────────────────────────────────────────────────────────────────
  // BASEMAP JALAN — cache tile raster (Opsi B)
  // ─────────────────────────────────────────────────────────────────────────

  /// basemapId cache road-tile untuk sebuah company (`roads_<id>`) atau data
  /// lokal (`roads_local`). Konsisten dengan penyimpanan `.pbf` per-company.
  static String roadBasemapId(int? companyId) =>
      companyId != null ? 'roads_$companyId' : 'roads_local';

  /// Cari companyId dari path data jalan aktif dengan mencocokkan daftar road
  /// cloud tersimpan. Tak cocok / null (mis. file lokal import) → null → local.
  static int? companyIdForPath(String? activePath, List<DownloadedRoad> saved) {
    if (activePath == null) return null;
    for (final d in saved) {
      if (d.path == activePath) return d.id;
    }
    return null;
  }

  /// Kosongkan cache road-tile agar di-regenerate lazy. Dipanggil saat data
  /// jalan berubah (update/ganti) atau dihapus. Gagal-diam (cache best-effort).
  Future<void> clearRoadTileCache(int? companyId) async {
    try {
      await TileCacheSqliteService().clearCache(roadBasemapId(companyId));
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OSM DATA MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the path of the loaded OSM .pbf file, or null if none.
  Future<String?> getOsmFilePath() async {
    final prefs = await SharedPreferences.getInstance();
    final path  = prefs.getString(_prefOsmKey);
    if (path == null) return null;
    if (!File(path).existsSync()) {
      // File was deleted — clear the pref
      await prefs.remove(_prefOsmKey);
      return null;
    }
    return path;
  }

  /// Copy a .pbf file picked by the user into app documents directory
  /// and save the path for the routing engine.
  Future<String?> importOsmFile(String sourcePath) async {
    try {
      final src = File(sourcePath);
      if (!src.existsSync()) return null;

      final dir  = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/osm_routing.pbf');

      await src.copy(dest.path);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefOsmKey, dest.path);

      // Ganti data jalan lokal → cache road-tile lama basi → bersihkan
      // (di-regenerate lazy dari .pbf baru).
      await clearRoadTileCache(null);

      logDebug('✅ RoutingService: OSM file imported → ${dest.path}', tag: 'ROUTING');
      return dest.path;
    } catch (e) {
      logError('❌ RoutingService: importOsmFile error — $e', tag: 'ROUTING');
      return null;
    }
  }

  /// Delete the stored OSM file and reset the routing engine.
  Future<void> deleteOsmFile() async {
    final path = await getOsmFilePath();
    if (path != null) {
      try { await File(path).delete(); } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefOsmKey);
    _isInitialized = false;
    // Hapus data jalan lokal → hapus juga cache road-tile-nya.
    await clearRoadTileCache(null);
    logDebug('🗑️ RoutingService: OSM file deleted', tag: 'ROUTING');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SERVER ROAD DATA (download dari TR_ROAD, filter company)
  // ─────────────────────────────────────────────────────────────────────────

  final ApiService _api = ApiService();

  /// Daftar company (dalam scope user) yang bisa diunduh data jalannya.
  Future<List<DownloadableCompany>> fetchDownloadableCompanies() async {
    try {
      final resp = await _api.get(ApiConfig.roadsCompaniesEndpoint);
      if (resp.statusCode != 200) return [];
      return parseCompanies(resp.body);
    } catch (e) {
      logError('❌ RoutingService: fetchDownloadableCompanies — $e', tag: 'ROUTING');
      return [];
    }
  }

  Future<String> _roadsDirPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/roads');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  Future<String> _roadFilePath(int id) async => '${await _roadsDirPath()}/roads_$id.pbf';

  Future<List<Map<String, dynamic>>> _readIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefDownloadedIndex);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<Map<String, dynamic>> idx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDownloadedIndex, jsonEncode(idx));
  }

  /// Apakah road data company sudah tersimpan lokal.
  Future<bool> isRoadDownloaded(int id) async => File(await _roadFilePath(id)).existsSync();

  /// Daftar road data yang tersimpan lokal (bisa dipilih offline).
  Future<List<DownloadedRoad>> listDownloadedRoads() async {
    final idx = await _readIndex();
    final out = <DownloadedRoad>[];
    for (final e in idx) {
      final id = (e['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      final path = await _roadFilePath(id);
      if (File(path).existsSync()) {
        out.add(DownloadedRoad(id: id, name: e['name']?.toString() ?? 'Company #$id', path: path));
      }
    }
    return out;
  }

  Future<bool> _activate(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefOsmKey, path);
    _isInitialized = false;
    return initialize(forceRebuild: true);
  }

  /// Pakai road data yang sudah tersimpan (offline) → build engine, tanpa unduh.
  Future<RoadPrepareResult> activateDownloadedRoads(int id, {void Function(String)? onProgress}) async {
    if (!_routingSupported) {
      return const RoadPrepareResult(RoadPrepareStatus.error, 'Routing tidak tersedia di perangkat ini');
    }
    final path = await _roadFilePath(id);
    if (!File(path).existsSync()) {
      return const RoadPrepareResult(RoadPrepareStatus.empty, 'Data belum diunduh');
    }
    onProgress?.call('Building routing engine…');
    final ok = await _activate(path);
    return ok
        ? const RoadPrepareResult(RoadPrepareStatus.ready, 'Routing siap digunakan')
        : const RoadPrepareResult(RoadPrepareStatus.error, 'Gagal membangun routing engine');
  }

  /// Hapus road data tersimpan sebuah company.
  Future<void> deleteDownloadedRoads(int id) async {
    final path = await _roadFilePath(id);
    final f = File(path);
    if (f.existsSync()) {
      try { f.deleteSync(); } catch (_) {}
    }
    final idx = await _readIndex()
      ..removeWhere((e) => (e['id'] as num?)?.toInt() == id);
    await _writeIndex(idx);

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_prefOsmKey) == path) {
      await prefs.remove(_prefOsmKey);
      _isInitialized = false;
    }

    // Hapus data jalan company → hapus juga cache road-tile-nya.
    await clearRoadTileCache(id);
  }

  /// Unduh .osm.pbf sebuah company, simpan PER-COMPANY (bisa dipakai offline
  /// lagi tanpa unduh ulang), LALU pasang ke GraphHopper hingga siap.
  Future<RoadPrepareResult> downloadAndPrepareRoads(
    int companyId, {
    String? name,
    void Function(String message)? onProgress,
  }) async {
    if (!_routingSupported) {
      return const RoadPrepareResult(RoadPrepareStatus.error, 'Routing tidak tersedia di perangkat ini');
    }
    try {
      onProgress?.call('Downloading road data…');
      final resp = await _api.get('${ApiConfig.roadsOsmEndpoint}?id=$companyId');

      if (resp.statusCode == 404) {
        return const RoadPrepareResult(
            RoadPrepareStatus.empty, 'Data jalan belum tersedia untuk company ini.');
      }
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        return RoadPrepareResult(RoadPrepareStatus.error, 'Gagal mengunduh (HTTP ${resp.statusCode})');
      }

      // Simpan per-company: roads/roads_<id>.pbf
      final dest = File(await _roadFilePath(companyId));
      await dest.writeAsBytes(resp.bodyBytes, flush: true);

      // Catat ke index (untuk daftar offline)
      final idx = await _readIndex()
        ..removeWhere((e) => (e['id'] as num?)?.toInt() == companyId)
        ..add({'id': companyId, 'name': name ?? 'Company #$companyId'});
      await _writeIndex(idx);

      // Update/ganti data jalan company ini → cache road-tile lama basi →
      // bersihkan agar di-regenerate lazy dari .pbf baru.
      await clearRoadTileCache(companyId);

      onProgress?.call('Building routing engine…');
      final ok = await _activate(dest.path);
      if (!ok) {
        return const RoadPrepareResult(RoadPrepareStatus.error, 'Gagal membangun routing engine');
      }
      return const RoadPrepareResult(RoadPrepareStatus.ready, 'Routing siap digunakan');
    } catch (e) {
      logError('❌ RoutingService: downloadAndPrepareRoads — $e', tag: 'ROUTING');
      return RoadPrepareResult(RoadPrepareStatus.error, 'Error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ENGINE LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  /// Initialize GraphHopper with the stored OSM file.
  /// Returns false if no OSM file exists or platform is iOS.
  Future<bool> initialize({bool forceRebuild = false}) async {
    if (!_isAndroid) {
      // iOS: pakai mesin Dart offline (bukan GraphHopper).
      return _initializeIos(forceRebuild: forceRebuild);
    }

    if (_isInitialized && !forceRebuild) return true;

    final osmPath = await getOsmFilePath();
    if (osmPath == null) {
      logWarn('⚠️ RoutingService: No OSM data — import a .pbf file first', tag: 'ROUTING');
      return false;
    }

    try {
      logDebug('🗺️ RoutingService: Initializing GraphHopper… (forceRebuild=$forceRebuild)', tag: 'ROUTING');
      // 3-minute safety-net timeout. GraphHopper without CH finishes in seconds
      // for typical local PBF files; this guard prevents indefinite UI hang if
      // the Kotlin side crashes silently.
      final ok = await _channel
          .invokeMethod<bool>('initialize', {
            'osmPath':      osmPath,
            'forceRebuild': forceRebuild,
          })
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () {
              logDebug('⏰ RoutingService: Initialize timeout (3 min)', tag: 'ROUTING');
              return null;
            },
          ) ?? false;
      _isInitialized = ok;
      if (ok) {
        logInfo('RoutingService siap', tag: 'ROUTING');
      } else {
        logError('RoutingService: init gagal', tag: 'ROUTING');
      }
      return ok;
    } on PlatformException catch (e) {
      logError('❌ RoutingService: Platform error — ${e.code}: ${e.message}', tag: 'ROUTING');
      return false;
    } on TimeoutException {
      logDebug('⏰ RoutingService: Init timed out', tag: 'ROUTING');
      return false;
    }
  }

  /// Force re-initialize after importing a new OSM file.
  /// Deletes the stale graph cache so GraphHopper rebuilds from the new PBF.
  Future<bool> reinitialize() async {
    _isInitialized = false;
    if (!_isAndroid) _iosEngine.dispose();
    return initialize(forceRebuild: true);
  }

  // ─── iOS: mesin Dart offline (terpisah dari jalur Android) ──────────────────

  /// Init mesin Dart dari `.pbf` tersimpan (dibangun di isolate). Bila flag
  /// [iosEngineEnabled] false → tetap graceful (false), tanpa efek ke Android.
  Future<bool> _initializeIos({bool forceRebuild = false}) async {
    if (!iosEngineEnabled) {
      logDebug('ℹ️ RoutingService: iOS Dart engine disabled', tag: 'ROUTING');
      return false;
    }
    if (_isInitialized && !forceRebuild) return true;

    final osmPath = await getOsmFilePath();
    if (osmPath == null) {
      logWarn('⚠️ RoutingService(iOS): No OSM data — import a .pbf first', tag: 'ROUTING');
      return false;
    }
    _isInitialized = await _iosEngine.initialize(osmPath, forceRebuild: forceRebuild);
    logError((_isInitialized
        ? '✅ RoutingService(iOS): Dart engine ready'
        : '❌ RoutingService(iOS): Dart engine init failed').toString(), tag: 'ROUTING');
    return _isInitialized;
  }

  Future<RouteResult?> _calculateRouteIos({
    required LatLng from,
    required LatLng to,
    required String profile,
  }) async {
    if (!iosEngineEnabled) return null;
    if (!_isInitialized) {
      final ok = await _initializeIos();
      if (!ok) return null;
    }
    return _iosEngine.calculateRoute(
      fromLat: from.latitude,
      fromLon: from.longitude,
      toLat: to.latitude,
      toLon: to.longitude,
      profile: profile,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ROUTING
  // ─────────────────────────────────────────────────────────────────────────

  /// Calculate a route from [from] to [to].
  /// [profile] — 'car' or 'foot'
  /// Returns null on error or when engine not initialized.
  Future<RouteResult?> calculateRoute({
    required LatLng from,
    required LatLng to,
    String profile = 'car',
  }) async {
    if (!_isAndroid) {
      // iOS: hitung lewat mesin Dart offline.
      return _calculateRouteIos(from: from, to: to, profile: profile);
    }

    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return null;
    }

    try {
      logDebug('🗺️ RoutingService: Calculating route $profile ${from.latitude},${from.longitude} → ${to.latitude},${to.longitude}', tag: 'ROUTING');
      final raw = await _channel.invokeMethod<Map>('calculateRoute', {
        'fromLat': from.latitude,
        'fromLon': from.longitude,
        'toLat':   to.latitude,
        'toLon':   to.longitude,
        'profile': profile,
      });
      if (raw == null) return null;
      final result = RouteResult.fromMap(raw);
      logDebug('✅ RoutingService: Route ${result.formattedDistance} / ${result.formattedTime}', tag: 'ROUTING');
      return result;
    } on PlatformException catch (e) {
      logError('❌ RoutingService: Route error — ${e.message}', tag: 'ROUTING');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SNAP-TO-ROUTE  (port of RouteSnapper.java from analyzed APK)
  // ─────────────────────────────────────────────────────────────────────────

  /// Snap [position] to the nearest point on [routePoints].
  ///
  /// Uses perpendicular foot projection on each segment (a→b):
  ///   t = dot(p-a, b-a) / |b-a|²    clamped to [0,1]
  ///   foot = a + t*(b-a)
  ///
  /// Off-route is flagged only when GPS is stable (accuracy ≤ 10m),
  /// matching APK's `isGPSStable()` guard.
  SnappedResult snapToRoute(
    LatLng position,
    List<LatLng> routePoints,
    double accuracy,
  ) {
    if (routePoints.length < 2) {
      return SnappedResult(
        point:           position,
        segmentIndex:    0,
        distanceToRoute: 0,
        isOffRoute:      false,
      );
    }

    final allowable = max(accuracy, _offRouteDist);
    double minDist  = double.infinity;
    LatLng best     = routePoints.first;
    int    bestSeg  = 0;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final a = routePoints[i];
      final b = routePoints[i + 1];
      final foot = _perpendicularFoot(position, a, b);
      final d    = _haversine(position, foot);
      if (d < minDist) {
        minDist = d;
        best    = foot;
        bestSeg = i;
      }
    }

    final gpsStable = accuracy <= _gpsStableAccuracy;
    final offRoute  = gpsStable && minDist > allowable;

    return SnappedResult(
      point:           best,
      segmentIndex:    bestSeg,
      distanceToRoute: minDist,
      isOffRoute:      offRoute,
    );
  }

  /// Compute perpendicular foot of [p] onto segment [a]→[b].
  LatLng _perpendicularFoot(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = p.longitude, py = p.latitude;

    final dx = bx - ax, dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return a;

    final t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
    final tc = t.clamp(0.0, 1.0);

    return LatLng(ay + tc * dy, ax + tc * dx);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OFF-ROUTE  (NavigationHelper.isOffRoute)
  // ─────────────────────────────────────────────────────────────────────────

  bool isOffRoute(SnappedResult snap) => snap.isOffRoute;

  // ─────────────────────────────────────────────────────────────────────────
  // ROUTE COMPLETED  (NavigationHelper.isRouteCompleted)
  // ─────────────────────────────────────────────────────────────────────────

  bool isRouteCompleted(LatLng current, LatLng destination) {
    final dist = _haversine(current, destination);
    if (dist > _arrivedDist * 2) return false;
    // Within arrival distance → check bearing alignment (within ±10°)
    if (dist <= _arrivedDist) return true;
    final bearing = _bearing(current, destination);
    final bearingDiff = ((bearing - _bearing(destination, current)).abs() % 360);
    return dist < _arrivedDist && bearingDiff <= _arrivedBearing;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INSTRUCTION UPDATE
  // ─────────────────────────────────────────────────────────────────────────

  /// Find the active instruction based on the current segment index.
  /// (The maneuver you are currently on — kept for backward compatibility.)
  RouteInstruction? updateInstruction(
    int segmentIndex,
    List<RouteInstruction> instructions,
  ) {
    RouteInstruction? active;
    for (final instr in instructions) {
      if (instr.interval <= segmentIndex) {
        active = instr;
      } else {
        break;
      }
    }
    return active;
  }

  /// Index of the UPCOMING instruction — the first maneuver ahead of the
  /// current segment (interval > segmentIndex). This is what should be shown
  /// to the driver, Google-style ("in 200 m turn left"), so the prompt appears
  /// BEFORE the turn rather than after it.
  int? upcomingInstructionIndex(
    int segmentIndex,
    List<RouteInstruction> instructions,
  ) {
    for (int i = 0; i < instructions.length; i++) {
      if (instructions[i].interval > segmentIndex) return i;
    }
    return null;
  }

  /// The upcoming maneuver ahead of the current segment.
  /// Falls back to the last instruction (e.g. "arrive") when none remain ahead.
  RouteInstruction? upcomingInstruction(
    int segmentIndex,
    List<RouteInstruction> instructions,
  ) {
    if (instructions.isEmpty) return null;
    final idx = upcomingInstructionIndex(segmentIndex, instructions);
    return idx == null ? instructions.last : instructions[idx];
  }

  /// The maneuver AFTER the upcoming one — used for the "then …" preview row.
  RouteInstruction? followingInstruction(
    int segmentIndex,
    List<RouteInstruction> instructions,
  ) {
    final idx = upcomingInstructionIndex(segmentIndex, instructions);
    if (idx == null || idx + 1 >= instructions.length) return null;
    return instructions[idx + 1];
  }

  /// Distance to the next instruction from current segment (meters).
  double distanceToNextInstruction(
    LatLng current,
    int segmentIndex,
    List<RouteInstruction> instructions,
    List<RoutePoint> routePoints,
  ) {
    // Find next instruction after current segment
    for (final instr in instructions) {
      if (instr.interval > segmentIndex) {
        // Sum segment distances from current position to that waypoint
        double dist = 0;
        for (int i = segmentIndex; i < instr.interval && i < routePoints.length - 1; i++) {
          dist += _haversinePoints(routePoints[i], routePoints[i + 1]);
        }
        return dist;
      }
    }
    return 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // U-TURN DETECTION  (NavigationHelper.detectUTurns — sliding window)
  // ─────────────────────────────────────────────────────────────────────────

  /// Call on each new GPS fix while navigating.
  /// Returns true if a U-turn is detected in the sliding window.
  ///
  /// APK criteria:
  ///   windowSize = 10 points
  ///   bearingChange(first → last) > 150°
  ///   dist(first → last) < 50m
  ///   avgSpeed < 5 km/h
  bool detectUTurn(List<TrackPoint> window) {
    if (window.length < 10) return false;
    final w = window.length < 20 ? window : window.sublist(window.length - 10);

    // Arah gerak paruh-AWAL vs paruh-AKHIR window. U-turn = arah berbalik
    // ~180°. (Bug lama membandingkan A→B dengan B→A yang SELALU 180°, sehingga
    // U-turn palsu muncul tiap kali bergerak pelan dalam radius kecil.)
    final mid = w.length ~/ 2;
    final entryBearing = _bearing(w.first.position, w[mid].position);
    final exitBearing = _bearing(w[mid].position, w.last.position);
    final bearingChange = _bearingChangeDeg(entryBearing, exitBearing);

    final span = _haversine(w.first.position, w.last.position);

    final avgSpeedKmh = w.map((p) => p.speedKmh ?? 0.0).reduce((a, b) => a + b) /
        w.length;

    return bearingChange > _uTurnBearing &&
        span < _uTurnDist &&
        avgSpeedKmh < _uTurnSpeed;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MATH HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  double _haversine(LatLng a, LatLng b) =>
      _haversineCoords(a.latitude, a.longitude, b.latitude, b.longitude);

  double _haversinePoints(RoutePoint a, RoutePoint b) =>
      _haversineCoords(a.latitude, a.longitude, b.latitude, b.longitude);

  double _haversineCoords(double lat1, double lon1, double lat2, double lon2) {
    const r     = 6371000.0;
    const toRad = pi / 180;
    final dLat  = (lat2 - lat1) * toRad;
    final dLon  = (lon2 - lon1) * toRad;
    final sinLat = sin(dLat / 2);
    final sinLon = sin(dLon / 2);
    final a     = sinLat * sinLat +
        cos(lat1 * toRad) * cos(lat2 * toRad) *
            sinLon * sinLon;
    return r * 2 * asin(sqrt(a.clamp(0.0, 1.0)));
  }

  double _bearing(LatLng from, LatLng to) {
    const toRad = pi / 180;
    final dLon  = (to.longitude - from.longitude) * toRad;
    final lat1  = from.latitude * toRad;
    final lat2  = to.latitude   * toRad;
    final y     = cos(lat2) * sin(dLon);
    final x     = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _bearingChangeDeg(double b1, double b2) {
    final diff = ((b2 - b1 + 540) % 360) - 180;
    return diff.abs();
  }

}

/// Lightweight track point for U-turn sliding window
class TrackPoint {
  final LatLng position;
  final double? speedKmh;
  TrackPoint(this.position, this.speedKmh);
}
