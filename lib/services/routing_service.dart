import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/route_result.dart';
import 'api_service.dart';

/// Company yang bisa diunduh data jalannya (dari /mobile/roads/companies/).
class DownloadableCompany {
  final int id;
  final String name;
  final int roadCount;
  const DownloadableCompany({required this.id, required this.name, required this.roadCount});

  bool get hasData => roadCount > 0;
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

/// Routing service backed by GraphHopper on Android via MethodChannel.
/// On iOS the routing methods return null — handle gracefully.
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

      debugPrint('✅ RoutingService: OSM file imported → ${dest.path}');
      return dest.path;
    } catch (e) {
      debugPrint('❌ RoutingService: importOsmFile error — $e');
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
    debugPrint('🗑️ RoutingService: OSM file deleted');
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
      debugPrint('❌ RoutingService: fetchDownloadableCompanies — $e');
      return [];
    }
  }

  /// Unduh .osm.pbf sebuah company, simpan, LALU pasang ke GraphHopper hingga siap.
  /// Return status ready/empty/error (bukan sekadar file tersimpan).
  Future<RoadPrepareResult> downloadAndPrepareRoads(
    int companyId, {
    void Function(String message)? onProgress,
  }) async {
    if (!_isAndroid) {
      return const RoadPrepareResult(RoadPrepareStatus.error, 'Navigasi hanya tersedia di Android');
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

      // Simpan PBF (ekstensi .pbf → GraphHopper parse sebagai PBF)
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/osm_routing.pbf');
      await dest.writeAsBytes(resp.bodyBytes, flush: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefOsmKey, dest.path);
      _isInitialized = false;

      onProgress?.call('Building routing engine…');
      final ok = await initialize(forceRebuild: true);
      if (!ok) {
        return const RoadPrepareResult(RoadPrepareStatus.error, 'Gagal membangun routing engine');
      }
      return const RoadPrepareResult(RoadPrepareStatus.ready, 'Routing siap digunakan');
    } catch (e) {
      debugPrint('❌ RoutingService: downloadAndPrepareRoads — $e');
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
      debugPrint('ℹ️ RoutingService: GraphHopper not available on iOS');
      return false;
    }

    if (_isInitialized && !forceRebuild) return true;

    final osmPath = await getOsmFilePath();
    if (osmPath == null) {
      debugPrint('⚠️ RoutingService: No OSM data — import a .pbf file first');
      return false;
    }

    try {
      debugPrint('🗺️ RoutingService: Initializing GraphHopper… (forceRebuild=$forceRebuild)');
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
              debugPrint('⏰ RoutingService: Initialize timeout (3 min)');
              return null;
            },
          ) ?? false;
      _isInitialized = ok;
      debugPrint(ok ? '✅ RoutingService: Ready' : '❌ RoutingService: Init failed');
      return ok;
    } on PlatformException catch (e) {
      debugPrint('❌ RoutingService: Platform error — ${e.code}: ${e.message}');
      return false;
    } on TimeoutException {
      debugPrint('⏰ RoutingService: Init timed out');
      return false;
    }
  }

  /// Force re-initialize after importing a new OSM file.
  /// Deletes the stale graph cache so GraphHopper rebuilds from the new PBF.
  Future<bool> reinitialize() async {
    _isInitialized = false;
    return initialize(forceRebuild: true);
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
    if (!_isAndroid) return null;

    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return null;
    }

    try {
      debugPrint('🗺️ RoutingService: Calculating route $profile ${from.latitude},${from.longitude} → ${to.latitude},${to.longitude}');
      final raw = await _channel.invokeMethod<Map>('calculateRoute', {
        'fromLat': from.latitude,
        'fromLon': from.longitude,
        'toLat':   to.latitude,
        'toLon':   to.longitude,
        'profile': profile,
      });
      if (raw == null) return null;
      final result = RouteResult.fromMap(raw);
      debugPrint('✅ RoutingService: Route ${result.formattedDistance} / ${result.formattedTime}');
      return result;
    } on PlatformException catch (e) {
      debugPrint('❌ RoutingService: Route error — ${e.message}');
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

    final bearingChange = _bearingChangeDeg(
      _bearing(w.first.position, w.last.position),
      _bearing(w.last.position, w.first.position),
    );

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
