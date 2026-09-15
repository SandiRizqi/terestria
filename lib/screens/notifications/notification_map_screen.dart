import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoform_app/config/api_config.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/basemap_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/layer_model.dart';
import '../../models/route_result.dart';
import '../../services/basemap_service.dart';
import '../../services/layer_service.dart';
import '../../services/location_service_v2.dart';
import '../../services/routing_service.dart';
import '../../services/settings_service.dart';
import '../../services/tile_providers/sqlite_cached_tile_provider.dart';
import '../../mixins/routing_data_manager.dart';
import '../../mixins/map_tools_host.dart';
import '../../widgets/map/map_controls_column.dart';
import '../../widgets/map/map_tool_button.dart';
import '../../theme/app_theme.dart';
import '../basemap/basemap_management_screen.dart';
import '../data_collection/widgets/user_location_marker.dart';
import '../navigation/widgets/instruction_bar.dart';
import '../navigation/widgets/step_list_sheet.dart';

/// Fullscreen map viewer for notification GeoJSON data.
/// Supports basemap switching, user GeoJSON layers, click-to-inspect,
/// notification overlay, and GraphHopper turn-by-turn routing.
class NotificationMapScreen extends StatefulWidget {
  final String geoJsonData;
  final String title;

  const NotificationMapScreen({
    super.key,
    required this.geoJsonData,
    this.title = 'Notification Map',
  });

  @override
  State<NotificationMapScreen> createState() => _NotificationMapScreenState();
}

class _NotificationMapScreenState extends State<NotificationMapScreen>
    with RoutingDataManager<NotificationMapScreen>,
        MapToolsHost<NotificationMapScreen> {
  // ─── Services ──────────────────────────────────────────────────────────────
  final MapController      _mapController  = MapController();
  final BasemapService     _basemapService = BasemapService();
  final LayerService       _layerService   = LayerService();
  final SettingsService    _settingsService = SettingsService();
  final LocationServiceV2  _locationService = LocationServiceV2();
  final RoutingService     _routingService  = RoutingService();

  // ─── Basemap & Layers ──────────────────────────────────────────────────────
  Basemap? _selectedBasemap;
  List<LayerModel> _layers = [];
  final Map<String, Map<String, dynamic>> _layerGeoJsonCache = {};

  // ─── GPS ───────────────────────────────────────────────────────────────────
  GeoPoint? _currentLocation;
  StreamSubscription<GeoPoint>? _locationSubscription;
  double _gpsBearing = 0.0; // device compass heading → UserLocationMarker
  StreamSubscription<CompassEvent>? _compassSub;
  DateTime? _lastCompassUpdate;

  // ─── Map state ─────────────────────────────────────────────────────────────
  double _currentBearing     = 0; // map rotation (compass widget + listener)
  LatLng _centerCoordinates  = const LatLng(-6.2088, 106.8456);

  // ─── Notification GeoJSON ──────────────────────────────────────────────────
  Map<String, dynamic>? _notificationGeoJson;
  bool   _isLoading   = true;
  String? _parseError;

  // ─── Click-to-inspect ─────────────────────────────────────────────────────
  Map<String, dynamic>? _selectedProperties;
  String? _selectedGeometryType;
  LatLng? _selectedLatLng;

  // ─── GraphHopper routing ──────────────────────────────────────────────────
  RouteResult?      _routeResult;
  LatLng?           _destinationPoint;
  String?           _destinationLabel;
  SnappedResult?    _snapped;
  int               _currentSegment  = 0;
  RouteInstruction? _currentInstruction;   // upcoming maneuver (shown to user)
  RouteInstruction? _followingInstruction; // maneuver after the upcoming one
  double            _distToNext      = 0;
  bool              _isNavigating    = false;
  bool              _isOffRoute      = false;
  bool              _isCalculating   = false;
  Timer?            _recalcDebounce;
  final List<TrackPoint> _uTurnWindow = [];

  // ─── OSM ──────────────────────────────────────────────────────────────────
  // OSM management UI + server road-download berada di RoutingDataManager mixin;
  // `isImportingOsm` dimiliki mixin. Field & kait di bawah menjembataninya.
  String? _osmFilePath;
  bool    _isInitializingRouter = false;

  // ─── Kait RoutingDataManager ────────────────────────────────────────────────
  @override
  RoutingService get routingService => _routingService;
  @override
  String? get osmFilePath => _osmFilePath;
  @override
  set osmFilePath(String? v) => _osmFilePath = v;
  @override
  Future<void> initRoutingEngine({bool reinit = false}) =>
      _initRouter(reinit: reinit);
  @override
  void showRoutingSnack(String message) => _showSnackBar(message);

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _compassSub?.cancel();
    _recalcDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _settingsService.initialize();

    // Parse GeoJSON (offline-safe)
    try {
      _notificationGeoJson = jsonDecode(widget.geoJsonData) as Map<String, dynamic>;
    } catch (e) {
      _parseError = 'Failed to parse GeoJSON: $e';
    }

    // Load basemap + layers + OSM state in parallel (all offline-safe)
    await Future.wait([
      _loadBasemap(),
      _loadActiveLayers(),
      _loadOsmState(),
    ]);

    if (mounted) {
      setState(() => _isLoading = false);
      if (_notificationGeoJson != null && _parseError == null) {
        Future.delayed(const Duration(milliseconds: 500), _fitToNotificationBounds);
      }
    }

    // Fire-and-forget: location + compass do NOT block map rendering
    _initLocation();
    _initCompass();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INITIALIZATION HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadBasemap() async {
    final basemap = await _basemapService.getSelectedBasemap();
    if (mounted) setState(() => _selectedBasemap = basemap);
  }

  Future<void> _loadActiveLayers() async {
    final layers = await _layerService.loadLayers();
    final cache  = <String, Map<String, dynamic>>{};
    for (final layer in layers) {
      if (layer.isActive) {
        final geoJson = await _layerService.readGeoJson(layer.filePath);
        if (geoJson != null) cache[layer.id] = geoJson;
      }
    }
    if (mounted) {
      setState(() {
        _layers = layers;
        _layerGeoJsonCache.clear();
        _layerGeoJsonCache.addAll(cache);
      });
    }
  }

  Future<void> _toggleLayerActive(LayerModel layer, bool active) async {
    await _layerService.toggleLayer(layer.id, active);
    await _loadActiveLayers();
  }

  /// Initialize GPS — offline-safe, map renders without it.
  void _initLocation() async {
    try {
      await _locationService.initialize();
      await _locationService.loadLocationSettings();
    } catch (e) {
      debugPrint('Location init failed (offline?): $e');
      return;
    }

    // One-shot for initial map position
    try {
      final loc = await _locationService.getCurrentLocation();
      if (loc != null && mounted) setState(() => _currentLocation = loc);
    } catch (e) {
      debugPrint('One-shot location failed: $e');
    }

    // Continuous stream → routing logic
    _locationSubscription = _locationService.getActiveLocationStream().listen(
      _onLocationUpdate,
      onError: (e) => debugPrint('Location stream error: $e'),
    );
  }

  void _initCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      final now = DateTime.now();
      if (_lastCompassUpdate != null &&
          now.difference(_lastCompassUpdate!).inMilliseconds < 100) return;
      _lastCompassUpdate = now;
      if (event.heading != null && mounted) {
        setState(() => _gpsBearing = event.heading!);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GPS UPDATE → snap-to-route when navigating
  // ─────────────────────────────────────────────────────────────────────────

  void _onLocationUpdate(GeoPoint loc) {
    if (!mounted) return;
    final newLatLng = LatLng(loc.latitude, loc.longitude);

    // U-turn sliding window
    _uTurnWindow.add(TrackPoint(newLatLng, loc.speed));
    if (_uTurnWindow.length > 20) _uTurnWindow.removeAt(0);

    if (_isNavigating && _routeResult != null) {
      final snap = _routingService.snapToRoute(
        newLatLng,
        _routeResult!.latLngs,
        loc.accuracy ?? 25.0,
      );
      _currentSegment = snap.segmentIndex;

      // Show the UPCOMING maneuver (ahead of current segment) so the prompt
      // appears BEFORE the turn — same Google-style logic as NavigationScreen.
      final instr = _routingService.upcomingInstruction(
        _currentSegment,
        _routeResult!.instructions,
      );
      final following = _routingService.followingInstruction(
        _currentSegment,
        _routeResult!.instructions,
      );
      final distNext = _routingService.distanceToNextInstruction(
        snap.point,
        _currentSegment,
        _routeResult!.instructions,
        _routeResult!.points,
      );

      // Off-route → debounced recalculate
      if (snap.isOffRoute && !_isOffRoute) {
        _recalcDebounce?.cancel();
        _recalcDebounce = Timer(const Duration(seconds: 3), () {
          if (_isNavigating && _destinationPoint != null) {
            _calculateRoute(_destinationPoint!, _destinationLabel);
          }
        });
      }

      // Arrival check
      final dest = _destinationPoint;
      if (dest != null && _routingService.isRouteCompleted(snap.point, dest)) {
        _onArrived();
        return;
      }

      setState(() {
        _currentLocation      = loc;
        _snapped              = snap;
        _isOffRoute           = snap.isOffRoute;
        _currentInstruction   = instr;
        _followingInstruction = following;
        _distToNext           = distNext;
      });
    } else {
      setState(() {
        _currentLocation = loc;
        _snapped         = null;
        _isOffRoute      = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OSM MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadOsmState() async {
    final path = await _routingService.getOsmFilePath();
    if (!mounted) return;
    setState(() => _osmFilePath = path);
    // Eagerly init GH in background so it's ready when user taps Navigate
    if (path != null) _initRouter();
  }

  Future<void> _initRouter({bool reinit = false}) async {
    if (_isInitializingRouter) return;
    if (mounted) setState(() => _isInitializingRouter = true);
    try {
      final ok = reinit
          ? await _routingService.reinitialize()
          : await _routingService.initialize();
      if (!mounted) return;
      if (!ok) {
        _showSnackBar('⚠️ Routing engine failed to load. Try re-importing the routing file.');
      }
    } catch (e) {
      if (mounted) _showSnackBar('❌ Routing init error: $e');
    } finally {
      if (mounted) setState(() => _isInitializingRouter = false);
    }
  }


  // ─────────────────────────────────────────────────────────────────────────
  // GRAPHHOPPER ROUTING
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _calculateRoute(LatLng to, String? label) async {
    if (!isRoutingAvailable) { showRoutingUnavailableDialog(); return; }
    if (_isInitializingRouter) {
      _showSnackBar('⏳ Routing engine is preparing, please wait...');
      return;
    }

    final gps = _currentLocation;
    if (gps == null) {
      _showSnackBar('⚠️ GPS not available yet');
      return;
    }

    if (_osmFilePath == null) {
      showOsmMissingDialog();
      return;
    }

    setState(() {
      _isCalculating      = true;
      _isOffRoute         = false;
      _destinationLabel   = label;
      _selectedProperties = null; // close properties popup
    });

    try {
      final from   = LatLng(gps.latitude, gps.longitude);
      final result = await _routingService.calculateRoute(from: from, to: to);

      if (!mounted) return;

      if (result == null) {
        _showSnackBar('❌ Route calculation failed. Make sure routing data covers this area.');
        return;
      }

      setState(() {
        _routeResult        = result;
        _destinationPoint   = to;
        _currentSegment     = 0;
        _currentInstruction = _routingService.upcomingInstruction(
          0, result.instructions,
        );
        _followingInstruction = _routingService.followingInstruction(
          0, result.instructions,
        );
      });

      _fitRouteBounds(result.latLngs);
    } catch (e) {
      if (mounted) _showSnackBar('❌ Route error: $e');
    } finally {
      if (mounted) setState(() => _isCalculating = false);
    }
  }

  void _showStepList() {
    final route = _routeResult;
    if (route == null) return;
    showStepListSheet(context, route: route, currentSegment: _currentSegment);
  }

  void _startGhNavigation() {
    if (_routeResult == null) return;
    setState(() {
      _isNavigating = true;
      _uTurnWindow.clear();
    });
    _showSnackBar('▶️ Navigation started');
  }

  /// Stop turn-by-turn guidance but keep route visible on map.
  void _stopNavigation() {
    _recalcDebounce?.cancel();
    setState(() {
      _isNavigating       = false;
      _isOffRoute         = false;
      _currentInstruction = null;
      _followingInstruction = null;
    });
  }

  /// Clear route + stop navigation entirely.
  void _clearRoute() {
    _recalcDebounce?.cancel();
    setState(() {
      _isNavigating       = false;
      _isOffRoute         = false;
      _routeResult        = null;
      _destinationPoint   = null;
      _destinationLabel   = null;
      _snapped            = null;
      _currentInstruction = null;
      _followingInstruction = null;
      _distToNext         = 0;
    });
  }

  void _onArrived() {
    _clearRoute();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.flag_rounded, color: Colors.green),
          SizedBox(width: 8),
          Text('Arrived'),
        ]),
        content: const Text('You have arrived at your destination.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _fitRouteBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude,  maxLat = points.first.latitude;
    double minLon = points.first.longitude, maxLon = points.first.longitude;
    for (final p in points) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds:  LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon)),
          padding: const EdgeInsets.all(60),
        ),
      );
    } catch (_) {}
  }

  List<Polyline> _buildRoutePolylines() {
    final all = _routeResult!.latLngs;
    if (_isNavigating && _currentSegment > 0 && _currentSegment < all.length) {
      final passed    = all.sublist(0, _currentSegment + 1);
      final remaining = all.sublist(_currentSegment);
      return [
        Polyline(points: passed,    color: Colors.grey.shade400, strokeWidth: 5),
        Polyline(
          points:      remaining,
          color:       Colors.blue.shade600,
          strokeWidth: 6,
          pattern:     _isOffRoute
              ? StrokePattern.dashed(segments: const [12, 8])
              : const StrokePattern.solid(),
        ),
      ];
    }
    return [
      Polyline(
        points:      all,
        color:       _isOffRoute ? Colors.orange : Colors.blue.shade600,
        strokeWidth: 6,
        pattern:     _isOffRoute
            ? StrokePattern.dashed(segments: const [12, 8])
            : const StrokePattern.solid(),
      ),
    ];
  }

  Marker _buildDestinationMarker() => Marker(
        point:  _destinationPoint!,
        width:  36,
        height: 36,
        child:  const Icon(Icons.location_on_rounded, color: Colors.red, size: 36),
      );

  Marker _buildSnappedMarker() => Marker(
        point:  _snapped!.point,
        width:  14,
        height: 14,
        child:  Container(
          decoration: BoxDecoration(
            color:  Colors.white,
            shape:  BoxShape.circle,
            border: Border.all(color: Colors.blue.shade700, width: 3),
          ),
        ),
      );

  // ═══════════════════════════════════════════════════════════
  // Map Tap → find nearest feature and show properties
  // ═══════════════════════════════════════════════════════════

  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    if (_notificationGeoJson == null) return;

    final features = _notificationGeoJson!['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) return;

    Map<String, dynamic>? nearestProps;
    String? nearestType;
    double nearestDist = double.infinity;

    for (final f in features) {
      final feature = f as Map<String, dynamic>;
      final geom    = feature['geometry'] as Map<String, dynamic>?;
      final props   = feature['properties'] as Map<String, dynamic>? ?? {};
      if (geom == null) continue;

      final type = geom['type'] as String? ?? '';
      final dist = _distanceToFeature(latlng, geom);

      if (dist < nearestDist) {
        nearestDist  = dist;
        nearestProps = props;
        nearestType  = type;
      }
    }

    final zoom      = _mapController.camera.zoom;
    final threshold = 300 / math.pow(2, zoom);

    if (nearestProps != null && nearestDist < threshold) {
      LatLng? featureLatLng;
      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final props   = feature['properties'] as Map<String, dynamic>? ?? {};
        if (props == nearestProps) {
          final geom = feature['geometry'] as Map<String, dynamic>?;
          if (geom != null) featureLatLng = _getFeatureCentroid(geom);
          break;
        }
      }
      setState(() {
        _selectedProperties   = nearestProps;
        _selectedGeometryType = nearestType;
        _selectedLatLng       = featureLatLng;
      });
    } else {
      if (_selectedProperties != null) {
        setState(() {
          _selectedProperties   = null;
          _selectedGeometryType = null;
          _selectedLatLng       = null;
        });
      }
    }
  }

  LatLng? _getFeatureCentroid(Map<String, dynamic> geom) {
    final type   = geom['type'] as String? ?? '';
    final coords = geom['coordinates'];
    if (coords == null) return null;
    switch (type) {
      case 'Point':
        return LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
      case 'MultiPoint':
        final c = (coords as List).first;
        return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
      case 'LineString':
        final mid = (coords as List)[coords.length ~/ 2];
        return LatLng((mid[1] as num).toDouble(), (mid[0] as num).toDouble());
      case 'MultiLineString':
        final line = (coords as List).first as List;
        final mid  = line[line.length ~/ 2];
        return LatLng((mid[1] as num).toDouble(), (mid[0] as num).toDouble());
      case 'Polygon':
        final ring = (coords as List)[0] as List;
        double latSum = 0, lngSum = 0;
        for (final c in ring) { latSum += (c[1] as num).toDouble(); lngSum += (c[0] as num).toDouble(); }
        return LatLng(latSum / ring.length, lngSum / ring.length);
      case 'MultiPolygon':
        final ring = ((coords as List).first as List).first as List;
        double latSum = 0, lngSum = 0;
        for (final c in ring) { latSum += (c[1] as num).toDouble(); lngSum += (c[0] as num).toDouble(); }
        return LatLng(latSum / ring.length, lngSum / ring.length);
      default:
        return null;
    }
  }

  double _distanceToFeature(LatLng tap, Map<String, dynamic> geom) {
    final type   = geom['type'] as String? ?? '';
    final coords = geom['coordinates'];
    if (coords == null) return double.infinity;
    switch (type) {
      case 'Point':       return _distToCoord(tap, coords as List<dynamic>);
      case 'MultiPoint':  return (coords as List<dynamic>).map((c) => _distToCoord(tap, c as List<dynamic>)).reduce(math.min);
      case 'LineString':  return _distToLine(tap, coords as List<dynamic>);
      case 'MultiLineString': return (coords as List<dynamic>).map((l) => _distToLine(tap, l as List<dynamic>)).reduce(math.min);
      case 'Polygon':     return _distToPolygon(tap, coords as List<dynamic>);
      case 'MultiPolygon': return (coords as List<dynamic>).map((p) => _distToPolygon(tap, p as List<dynamic>)).reduce(math.min);
      default:            return double.infinity;
    }
  }

  double _distToCoord(LatLng tap, List<dynamic> coord) {
    return _haversineApprox(tap, LatLng((coord[1] as num).toDouble(), (coord[0] as num).toDouble()));
  }

  double _distToLine(LatLng tap, List<dynamic> coords) {
    double min = double.infinity;
    for (final c in coords) { final d = _distToCoord(tap, c as List<dynamic>); if (d < min) min = d; }
    return min;
  }

  double _distToPolygon(LatLng tap, List<dynamic> rings) {
    double min = double.infinity;
    for (final ring in rings) {
      for (final c in ring as List<dynamic>) { final d = _distToCoord(tap, c as List<dynamic>); if (d < min) min = d; }
    }
    return min;
  }

  double _haversineApprox(LatLng a, LatLng b) {
    final dLat = (a.latitude  - b.latitude ).abs();
    final dLng = (a.longitude - b.longitude).abs();
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  // ═══════════════════════════════════════════════════════════
  // Basemap rendering
  // ═══════════════════════════════════════════════════════════

  List<Widget> _buildBasemapLayers(Basemap basemap) {
    if (basemap.useOverlayMode &&
        basemap.pdfOverlayImagePath != null &&
        basemap.hasPdfGeoreferencing) {
      final imageFile = File(basemap.pdfOverlayImagePath!);
      if (!imageFile.existsSync() ||
          basemap.pdfMinLat == null || basemap.pdfMinLon == null ||
          basemap.pdfMaxLat == null || basemap.pdfMaxLon == null ||
          basemap.pdfMinLat! >= basemap.pdfMaxLat! ||
          basemap.pdfMinLon! >= basemap.pdfMaxLon!) {
        return [_defaultTileLayer()];
      }
      try {
        final bounds = LatLngBounds(
          LatLng(basemap.pdfMinLat!, basemap.pdfMinLon!),
          LatLng(basemap.pdfMaxLat!, basemap.pdfMaxLon!),
        );
        return [
          _defaultTileLayer(),
          OverlayImageLayer(
            overlayImages: [
              OverlayImage(
                bounds:           bounds,
                imageProvider:    FileImage(imageFile),
                opacity:          1.0,
                gaplessPlayback:  true,
              ),
            ],
          ),
        ];
      } catch (_) {
        return [_defaultTileLayer()];
      }
    } else {
      return [
        TileLayer(
          urlTemplate: basemap.urlTemplate.startsWith('sqlite://') ||
                  basemap.urlTemplate.startsWith('overlay://')
              ? ''
              : basemap.urlTemplate,
          userAgentPackageName: ApiConfig.bundleName,
          minZoom: basemap.minZoom.toDouble(),
          maxZoom: basemap.maxZoom.toDouble(),
          tileProvider: SqliteCachedTileProvider(
            basemapId: basemap.id,
            maxStale:  const Duration(days: 30),
          ),
        ),
      ];
    }
  }

  TileLayer _defaultTileLayer() => TileLayer(
        urlTemplate:         'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: ApiConfig.bundleName,
      );

  // ═══════════════════════════════════════════════════════════
  // User GeoJSON layers
  // ═══════════════════════════════════════════════════════════

  List<Widget> _buildUserGeoJsonLayers() {
    final result = <Widget>[];
    for (final layer in _layers) {
      if (!layer.isActive) continue;
      final geoJson = _layerGeoJsonCache[layer.id];
      if (geoJson == null) continue;
      result.addAll(_renderGeoJson(
        geoJson,
        fillColor:   layer.style.fillColor,
        fillOpacity: layer.style.fillOpacity,
        strokeColor: layer.style.strokeColor,
        strokeWidth: layer.style.strokeWidth,
        pointSize:   layer.style.pointSize,
        labelField:  layer.labelField,
      ));
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // Notification GeoJSON rendering (per geometry type)
  // ═══════════════════════════════════════════════════════════

  List<Widget> _buildNotificationGeoJsonLayers() {
    if (_notificationGeoJson == null) return [];
    final features = _notificationGeoJson!['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) return [];

    final pointFeatures   = <dynamic>[];
    final lineFeatures    = <dynamic>[];
    final polygonFeatures = <dynamic>[];

    for (final f in features) {
      final feature = f as Map<String, dynamic>;
      final geom    = feature['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;
      final type = geom['type'] as String? ?? '';
      switch (type) {
        case 'Point':
        case 'MultiPoint':
          pointFeatures.add(f);
          break;
        case 'LineString':
        case 'MultiLineString':
          lineFeatures.add(f);
          break;
        case 'Polygon':
        case 'MultiPolygon':
          polygonFeatures.add(f);
          break;
      }
    }

    final result = <Widget>[];
    final s = _settingsService.settings;

    if (pointFeatures.isNotEmpty) {
      result.addAll(_renderGeoJson(
        {'type': 'FeatureCollection', 'features': pointFeatures},
        fillColor:   s.pointColor,
        fillOpacity: 1.0,
        strokeColor: s.pointColor,
        strokeWidth: 2.0,
        pointSize:   s.pointSize,
      ));
    }
    if (lineFeatures.isNotEmpty) {
      result.addAll(_renderGeoJson(
        {'type': 'FeatureCollection', 'features': lineFeatures},
        fillColor:   s.lineColor,
        fillOpacity: 1.0,
        strokeColor: s.lineColor,
        strokeWidth: s.lineWidth,
        pointSize:   s.pointSize,
      ));
    }
    if (polygonFeatures.isNotEmpty) {
      result.addAll(_renderGeoJson(
        {'type': 'FeatureCollection', 'features': polygonFeatures},
        fillColor:   s.polygonColor,
        fillOpacity: s.polygonOpacity,
        strokeColor: s.polygonColor,
        strokeWidth: s.lineWidth,
        pointSize:   s.pointSize,
      ));
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // Shared GeoJSON rendering engine
  // ═══════════════════════════════════════════════════════════

  List<Widget> _renderGeoJson(
    Map<String, dynamic> geoJson, {
    required Color  fillColor,
    required double fillOpacity,
    required Color  strokeColor,
    required double strokeWidth,
    required double pointSize,
    String? labelField,
  }) {
    final features     = geoJson['features'] as List<dynamic>? ?? [];
    final polylines    = <Polyline>[];
    final polygons     = <Polygon>[];
    final markers      = <Marker>[];
    final labelMarkers = <Marker>[];

    for (final f in features) {
      final feature = f as Map<String, dynamic>;
      final geom    = feature['geometry'] as Map<String, dynamic>?;
      final props   = feature['properties'] as Map<String, dynamic>? ?? {};
      if (geom == null) continue;

      final type  = geom['type'] as String? ?? '';
      final label = labelField != null ? props[labelField]?.toString() : null;

      switch (type) {
        case 'Point':
          final coords = geom['coordinates'] as List<dynamic>;
          final latlng = LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
          markers.add(_buildPointMarker(latlng, fillColor, fillOpacity, strokeColor, strokeWidth, pointSize));
          if (label != null) labelMarkers.add(_buildLabelMarker(latlng, label));
          break;
        case 'MultiPoint':
          for (final c in geom['coordinates'] as List<dynamic>) {
            final coords = c as List<dynamic>;
            final latlng = LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
            markers.add(_buildPointMarker(latlng, fillColor, fillOpacity, strokeColor, strokeWidth, pointSize));
            if (label != null) labelMarkers.add(_buildLabelMarker(latlng, label));
          }
          break;
        case 'LineString':
          final pts = _coordsToLatLng(geom['coordinates'] as List<dynamic>);
          if (pts.length >= 2) {
            polylines.add(Polyline(points: pts, color: strokeColor.withValues(alpha: fillOpacity), strokeWidth: strokeWidth));
            if (label != null) labelMarkers.add(_buildLabelMarker(pts[pts.length ~/ 2], label));
          }
          break;
        case 'MultiLineString':
          for (final line in geom['coordinates'] as List<dynamic>) {
            final pts = _coordsToLatLng(line as List<dynamic>);
            if (pts.length >= 2) {
              polylines.add(Polyline(points: pts, color: strokeColor.withValues(alpha: fillOpacity), strokeWidth: strokeWidth));
              if (label != null) labelMarkers.add(_buildLabelMarker(pts[pts.length ~/ 2], label));
            }
          }
          break;
        case 'Polygon':
          final rings = geom['coordinates'] as List<dynamic>;
          final outer = _coordsToLatLng(rings[0] as List<dynamic>);
          if (outer.length >= 3) {
            polygons.add(Polygon(points: outer, color: fillColor.withValues(alpha: fillOpacity), borderColor: strokeColor, borderStrokeWidth: strokeWidth));
            if (label != null) labelMarkers.add(_buildLabelMarker(_centroid(outer), label));
          }
          break;
        case 'MultiPolygon':
          for (final poly in geom['coordinates'] as List<dynamic>) {
            final rings = poly as List<dynamic>;
            final outer = _coordsToLatLng(rings[0] as List<dynamic>);
            if (outer.length >= 3) {
              polygons.add(Polygon(points: outer, color: fillColor.withValues(alpha: fillOpacity), borderColor: strokeColor, borderStrokeWidth: strokeWidth));
              if (label != null) labelMarkers.add(_buildLabelMarker(_centroid(outer), label));
            }
          }
          break;
      }
    }

    final result = <Widget>[];
    if (polylines.isNotEmpty)    result.add(PolylineLayer(polylines: polylines));
    if (polygons.isNotEmpty)     result.add(PolygonLayer(polygons: polygons));
    if (markers.isNotEmpty)      result.add(MarkerLayer(markers: markers));
    if (labelMarkers.isNotEmpty) result.add(MarkerLayer(markers: labelMarkers));
    return result;
  }

  Marker _buildPointMarker(LatLng latlng, Color fill, double opacity,
      Color stroke, double strokeW, double size) {
    final markerSize = size * 2;
    return Marker(
      point:  latlng,
      width:  markerSize,
      height: markerSize,
      child:  Container(
        decoration: BoxDecoration(
          color:  fill.withValues(alpha: opacity),
          shape:  BoxShape.circle,
          border: Border.all(color: stroke, width: strokeW.clamp(0.5, 3.0)),
        ),
      ),
    );
  }

  Marker _buildLabelMarker(LatLng latlng, String label) {
    return Marker(
      point:     latlng,
      width:     32,
      height:    32,
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 20,
        constraints: const BoxConstraints(maxWidth: 32),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color:        Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, height: 1.0),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          maxLines:  1,
        ),
      ),
    );
  }

  List<LatLng> _coordsToLatLng(List<dynamic> coords) {
    return coords.map((c) {
      final pair = c as List<dynamic>;
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();
  }

  LatLng _centroid(List<LatLng> points) {
    double sumLat = 0, sumLng = 0;
    for (final p in points) { sumLat += p.latitude; sumLng += p.longitude; }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }

  // ═══════════════════════════════════════════════════════════
  // Auto-fit to notification GeoJSON bounds
  // ═══════════════════════════════════════════════════════════

  void _fitToNotificationBounds() {
    if (_notificationGeoJson == null) return;
    final features = _notificationGeoJson!['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) return;

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    bool hasCoords = false;

    void processCoord(List<dynamic> coord) {
      final lng = (coord[0] as num).toDouble();
      final lat = (coord[1] as num).toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
      hasCoords = true;
    }
    void processCoords(List<dynamic> coords) {
      for (final c in coords) processCoord(c as List<dynamic>);
    }

    for (final f in features) {
      final geom        = (f as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;
      final type        = geom['type'] as String? ?? '';
      final coordinates = geom['coordinates'];
      if (coordinates == null) continue;

      switch (type) {
        case 'Point':                processCoord(coordinates as List<dynamic>); break;
        case 'MultiPoint':
        case 'LineString':           processCoords(coordinates as List<dynamic>); break;
        case 'MultiLineString':
        case 'Polygon':
          for (final ring in coordinates as List<dynamic>) processCoords(ring as List<dynamic>);
          break;
        case 'MultiPolygon':
          for (final poly in coordinates as List<dynamic>)
            for (final ring in poly as List<dynamic>) processCoords(ring as List<dynamic>);
          break;
      }
    }

    if (!hasCoords || !mounted) return;
    try {
      if (minLat == maxLat && minLng == maxLng) {
        minLat -= 0.005; maxLat += 0.005; minLng -= 0.005; maxLng += 0.005;
      }
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds:  LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
          padding: const EdgeInsets.all(60),
        ),
      );
    } catch (e) {
      debugPrint('Error fitting bounds: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Panels
  // ═══════════════════════════════════════════════════════════

  void _showLayersPanel() {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LayersPanelSheet(
        layers:   _layers,
        onToggle: (layer, active) => _toggleLayerActive(layer, active),
      ),
    );
  }

  void _showBasemapSelector() {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BasemapSelectorSheet(
        currentBasemap:     _selectedBasemap,
        onBasemapSelected:  (basemap) async {
          await _basemapService.setSelectedBasemap(basemap.id);
          await _loadBasemap();
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Properties popup (click-to-inspect)
  // ═══════════════════════════════════════════════════════════

  Widget _buildPropertiesPopup() {
    if (_selectedProperties == null) return const SizedBox.shrink();

    final navBarH    = MediaQuery.of(context).viewPadding.bottom;
    // Raise popup above route controls when a route is present
    final popupBottom = _routeResult != null ? navBarH + 160.0 : navBarH + 16.0;

    return Positioned(
      left:   16,
      right:  80,
      bottom: popupBottom,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 250),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color:        Colors.deepOrange.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Icon(_getGeomIcon(_selectedGeometryType ?? ''), color: Colors.deepOrange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Feature Properties',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.deepOrange[800]),
                      ),
                    ),
                    // Navigate button → GH routing
                    if (_selectedLatLng != null)
                      InkWell(
                        onTap: () {
                          final label = _selectedProperties?.values
                              .firstWhere((v) => v is String, orElse: () => null)
                              ?.toString();
                          _calculateRoute(_selectedLatLng!, label);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:        AppTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.navigation, size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Navigate', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _selectedProperties = null),
                      child: Icon(Icons.close, size: 18, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              // Properties list
              Flexible(
                child: _selectedProperties!.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No properties', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _selectedProperties!.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                        itemBuilder: (_, i) {
                          final entry = _selectedProperties!.entries.elementAt(i);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: Text(entry.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                                ),
                                Expanded(child: Text(entry.value?.toString() ?? 'null', style: const TextStyle(fontSize: 12))),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getGeomIcon(String type) {
    switch (type) {
      case 'Point':       case 'MultiPoint':      return Icons.place;
      case 'LineString':  case 'MultiLineString': return Icons.timeline;
      case 'Polygon':     case 'MultiPolygon':    return Icons.crop_square;
      default:                                    return Icons.map;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Route controls panel (replaces old bearing nav overlay)
  // ═══════════════════════════════════════════════════════════

  Widget _buildRouteControls() {
    if (_routeResult == null) return const SizedBox.shrink();
    final navBarH = MediaQuery.of(context).viewPadding.bottom;

    return Positioned(
      bottom: navBarH + 80,
      left:   16,
      right:  80,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:        _isNavigating ? AppTheme.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color:     Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset:    const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.route_rounded,
              color: _isNavigating ? Colors.white : AppTheme.primaryGreen,
              size:  20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isNavigating ? 'Navigating' : 'Route ready',
                    style: TextStyle(
                      fontSize:   13,
                      fontWeight: FontWeight.w700,
                      color:      _isNavigating ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    '${_routeResult!.formattedDistance}  •  ${_routeResult!.formattedTime}',
                    style: TextStyle(
                      fontSize: 11,
                      color:    _isNavigating ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            // Directions / step list (always available with a route)
            GestureDetector(
              onTap: _showStepList,
              child: Container(
                padding: const EdgeInsets.all(6),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _isNavigating
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.list_alt_rounded,
                  color: _isNavigating ? Colors.white : AppTheme.primaryGreen,
                  size: 18,
                ),
              ),
            ),
            // Start button (only when not yet navigating)
            if (!_isNavigating) ...[
              GestureDetector(
                onTap: _startGhNavigation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:        AppTheme.primaryGreen,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('Start', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Stop button (when navigating) or Clear button (X)
            if (_isNavigating)
              GestureDetector(
                onTap: _stopNavigation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:        Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_circle_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('Stop', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: _clearRoute,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color:        Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(color: Colors.red.shade200),
                  ),
                  child: Icon(Icons.close, color: Colors.red.shade400, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Small chips (coordinates / calculating / title)
  // ═══════════════════════════════════════════════════════════

  Widget _buildCoordinatesChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gps_fixed, size: 14, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            '${_centerCoordinates.latitude.toStringAsFixed(6)}, ${_centerCoordinates.longitude.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'monospace', color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatingChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color:        Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 10),
          Text('Calculating route...', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTitleChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:        Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Text(
        widget.title,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Export Data
  // ═══════════════════════════════════════════════════════════

  void _showExportDialog() {
    showModalBottomSheet(
      context:         context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text('Export Data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Choose format to export', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 16),
              _buildExportTile(Icons.code,       'GeoJSON',          '.geojson', Colors.green,  () { Navigator.pop(ctx); _exportGeoJson(); }),
              _buildExportTile(Icons.public,     'KML',              '.kml',     Colors.blue,   () { Navigator.pop(ctx); _exportKML(); }),
              _buildExportTile(Icons.folder_zip, 'Shapefile (ZIP)',  '.zip',     Colors.orange, () { Navigator.pop(ctx); _exportShapefile(); }),
              _buildExportTile(Icons.table_chart,'CSV',              '.csv',     Colors.purple, () { Navigator.pop(ctx); _exportCSV(); }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportTile(IconData icon, String title, String ext, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 22),
      ),
      title:    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('Export as $ext file', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: const Icon(Icons.chevron_right),
      onTap:    onTap,
    );
  }

  Future<void> _exportGeoJson() async {
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.geojson');
      await file.writeAsString(widget.geoJsonData);
      await _shareFile(file, 'application/geo+json');
    } catch (e) { _showExportError(e.toString()); }
  }

  Future<void> _exportKML() async {
    try {
      final geoJson  = jsonDecode(widget.geoJsonData) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>? ?? [];
      final buffer   = StringBuffer();
      buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
      buffer.writeln('<Document>');
      buffer.writeln('<name>${widget.title}</name>');

      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final geom    = feature['geometry'] as Map<String, dynamic>?;
        final props   = feature['properties'] as Map<String, dynamic>? ?? {};
        if (geom == null) continue;
        final type = geom['type'] as String? ?? '';
        final name = props.values.firstWhere((v) => v is String, orElse: () => 'Feature') ?? 'Feature';
        buffer.writeln('<Placemark>');
        buffer.writeln('<name>$name</name>');
        if (props.isNotEmpty) {
          buffer.writeln('<description><![CDATA[');
          for (final entry in props.entries) buffer.writeln('${entry.key}: ${entry.value}');
          buffer.writeln(']]></description>');
        }
        switch (type) {
          case 'Point':
            final coords = geom['coordinates'] as List;
            buffer.writeln('<Point><coordinates>${coords[0]},${coords[1]},${coords.length > 2 ? coords[2] : 0}</coordinates></Point>');
            break;
          case 'LineString':
            buffer.writeln('<LineString><coordinates>');
            for (final c in geom['coordinates'] as List) buffer.write('${c[0]},${c[1]},${(c as List).length > 2 ? c[2] : 0} ');
            buffer.writeln('</coordinates></LineString>');
            break;
          case 'Polygon':
            buffer.writeln('<Polygon><outerBoundaryIs><LinearRing><coordinates>');
            final rings = geom['coordinates'] as List;
            for (final c in rings[0] as List) buffer.write('${c[0]},${c[1]},${(c as List).length > 2 ? c[2] : 0} ');
            buffer.writeln('</coordinates></LinearRing></outerBoundaryIs></Polygon>');
            break;
          case 'MultiPoint':
            buffer.writeln('<MultiGeometry>');
            for (final coords in geom['coordinates'] as List)
              buffer.writeln('<Point><coordinates>${coords[0]},${coords[1]},${(coords as List).length > 2 ? coords[2] : 0}</coordinates></Point>');
            buffer.writeln('</MultiGeometry>');
            break;
          case 'MultiLineString':
            buffer.writeln('<MultiGeometry>');
            for (final line in geom['coordinates'] as List) {
              buffer.writeln('<LineString><coordinates>');
              for (final c in line as List) buffer.write('${c[0]},${c[1]},${(c as List).length > 2 ? c[2] : 0} ');
              buffer.writeln('</coordinates></LineString>');
            }
            buffer.writeln('</MultiGeometry>');
            break;
          case 'MultiPolygon':
            buffer.writeln('<MultiGeometry>');
            for (final poly in geom['coordinates'] as List) {
              buffer.writeln('<Polygon><outerBoundaryIs><LinearRing><coordinates>');
              for (final c in (poly as List)[0] as List) buffer.write('${c[0]},${c[1]},${(c as List).length > 2 ? c[2] : 0} ');
              buffer.writeln('</coordinates></LinearRing></outerBoundaryIs></Polygon>');
            }
            buffer.writeln('</MultiGeometry>');
            break;
        }
        buffer.writeln('</Placemark>');
      }
      buffer.writeln('</Document>');
      buffer.writeln('</kml>');
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.kml');
      await file.writeAsString(buffer.toString());
      await _shareFile(file, 'application/vnd.google-earth.kml+xml');
    } catch (e) { _showExportError(e.toString()); }
  }

  Future<void> _exportShapefile() async {
    try {
      final geoJson  = jsonDecode(widget.geoJsonData) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>? ?? [];
      if (features.isEmpty) { _showExportError('No features to export'); return; }

      final allKeys  = <String>{};
      for (final f in features) {
        final props = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? {};
        allKeys.addAll(props.keys);
      }
      final fieldNames = allKeys.take(10).toList();

      final csvBuffer = StringBuffer();
      csvBuffer.writeln('WKT,${fieldNames.join(',')}');
      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final geom    = feature['geometry'] as Map<String, dynamic>?;
        final props   = feature['properties'] as Map<String, dynamic>? ?? {};
        if (geom == null) continue;
        final wkt    = _geomToWKT(geom);
        final values = fieldNames.map((k) { final v = props[k]?.toString() ?? ''; return '"${v.replaceAll('"', '""')}"'; }).join(',');
        csvBuffer.writeln('"$wkt",$values');
      }

      const prjContent = 'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]';
      final archive    = Archive();
      final csvBytes   = csvBuffer.toString().codeUnits;
      final prjBytes   = prjContent.codeUnits;
      final gjBytes    = widget.geoJsonData.codeUnits;
      archive.addFile(ArchiveFile('export.csv',     csvBytes.length, csvBytes));
      archive.addFile(ArchiveFile('export.prj',     prjBytes.length, prjBytes));
      archive.addFile(ArchiveFile('export.geojson', gjBytes.length,  gjBytes));
      final zipData = ZipEncoder().encode(archive);
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.zip');
      await file.writeAsBytes(zipData);
      await _shareFile(file, 'application/zip');
    } catch (e) { _showExportError(e.toString()); }
  }

  String _geomToWKT(Map<String, dynamic> geom) {
    final type   = geom['type'] as String? ?? '';
    final coords = geom['coordinates'];
    switch (type) {
      case 'Point':         return 'POINT (${coords[0]} ${coords[1]})';
      case 'MultiPoint':    final pts0 = (coords as List).map((c) => '${c[0]} ${c[1]}').join(', '); return 'MULTIPOINT ($pts0)';
      case 'LineString':    final pts1 = (coords as List).map((c) => '${c[0]} ${c[1]}').join(', '); return 'LINESTRING ($pts1)';
      case 'MultiLineString':
        final lines = (coords as List).map((line) { final pts = (line as List).map((c) => '${c[0]} ${c[1]}').join(', '); return '($pts)'; }).join(', ');
        return 'MULTILINESTRING ($lines)';
      case 'Polygon':
        final rings0 = (coords as List).map((ring) { final pts = (ring as List).map((c) => '${c[0]} ${c[1]}').join(', '); return '($pts)'; }).join(', ');
        return 'POLYGON ($rings0)';
      case 'MultiPolygon':
        final polys = (coords as List).map((poly) { final rings = (poly as List).map((ring) { final pts = (ring as List).map((c) => '${c[0]} ${c[1]}').join(', '); return '($pts)'; }).join(', '); return '($rings)'; }).join(', ');
        return 'MULTIPOLYGON ($polys)';
      default: return 'POINT (0 0)';
    }
  }

  Future<void> _exportCSV() async {
    try {
      final geoJson  = jsonDecode(widget.geoJsonData) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>? ?? [];
      final allKeys  = <String>{};
      for (final f in features) {
        final props = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? {};
        allKeys.addAll(props.keys);
      }
      final fieldNames = allKeys.toList();
      final buffer     = StringBuffer();
      buffer.writeln('latitude,longitude,geometry_type,${fieldNames.join(',')}');

      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final geom    = feature['geometry'] as Map<String, dynamic>?;
        final props   = feature['properties'] as Map<String, dynamic>? ?? {};
        if (geom == null) continue;
        final type   = geom['type'] as String? ?? '';
        final c2     = geom['coordinates'];
        double lat = 0, lng = 0;
        switch (type) {
          case 'Point':      lng = (c2[0] as num).toDouble(); lat = (c2[1] as num).toDouble(); break;
          case 'LineString': final mid = (c2 as List)[c2.length ~/ 2]; lng = (mid[0] as num).toDouble(); lat = (mid[1] as num).toDouble(); break;
          case 'Polygon':    final ring = (c2 as List)[0] as List; final m2 = ring[ring.length ~/ 2]; lng = (m2[0] as num).toDouble(); lat = (m2[1] as num).toDouble(); break;
          default:
            if (c2 is List && c2.isNotEmpty) {
              final first = c2[0];
              if (first is List && first.isNotEmpty) {
                if (first[0] is num) { lng = (first[0] as num).toDouble(); lat = (first[1] as num).toDouble(); }
                else if (first[0] is List) { lng = ((first[0] as List)[0] as num).toDouble(); lat = ((first[0] as List)[1] as num).toDouble(); }
              }
            }
        }
        final values = fieldNames.map((k) { final v = props[k]?.toString() ?? ''; return '"${v.replaceAll('"', '""')}"'; }).join(',');
        buffer.writeln('$lat,$lng,"$type",$values');
      }
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(buffer.toString());
      await _shareFile(file, 'text/csv');
    } catch (e) { _showExportError(e.toString()); }
  }

  Future<void> _shareFile(File file, String mimeType) async {
    await Share.shareXFiles([XFile(file.path, mimeType: mimeType)], subject: widget.title);
  }

  void _showExportError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $message'), backgroundColor: Colors.red),
      );
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // Loading state — keep simple Scaffold with AppBar
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.primaryGreen,
          elevation:       0,
          title: Text(widget.title,
              style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Parse error state
    if (_parseError != null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.primaryGreen,
          elevation:       0,
          title: Text(widget.title,
              style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('Error Loading Map Data',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700])),
                const SizedBox(height: 8),
                Text(_parseError!, style: TextStyle(fontSize: 14, color: Colors.grey[600]), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    // ── Fullscreen map ──────────────────────────────────────────────────────
    final mq      = MediaQuery.of(context);
    final navBarH = mq.viewPadding.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody:             true,
      backgroundColor:        AppTheme.scaffoldBackground,
      body: Stack(
        children: [

          // ── MAP ────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-6.2088, 106.8456),
              initialZoom:   5,
              onTap: (pos, latlng) {
                if (handleMapToolsTap(latlng)) return;
                _onMapTap(pos, latlng);
              },
              onPositionChanged: (position, hasGesture) {
                final c = position.center;
                if (_centerCoordinates.latitude  != c.latitude ||
                    _centerCoordinates.longitude != c.longitude) {
                  setState(() => _centerCoordinates = c);
                }
                if (hasGesture) {
                  final bearing = _mapController.camera.rotation;
                  if (bearing != _currentBearing) setState(() => _currentBearing = bearing);
                }
              },
            ),
            children: [
              // Basemap
              if (_selectedBasemap != null)
                ..._buildBasemapLayers(_selectedBasemap!)
              else
                _defaultTileLayer(),

              // User GeoJSON layers
              ..._buildUserGeoJsonLayers(),

              // Notification GeoJSON
              ..._buildNotificationGeoJsonLayers(),

              // GH route polyline
              if (_routeResult != null)
                PolylineLayer(polylines: _buildRoutePolylines()),

              // Destination marker
              if (_destinationPoint != null)
                MarkerLayer(markers: [_buildDestinationMarker()]),

              // Snapped position dot (active navigation only)
              if (_snapped != null && _isNavigating)
                MarkerLayer(markers: [_buildSnappedMarker()]),

              // Accuracy ring — radius = akurasi (m); biru = fix bagus, amber = acquiring.
              if (_currentLocation != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(_currentLocation!.latitude,
                          _currentLocation!.longitude),
                      radius: (_currentLocation!.accuracy ?? 15).clamp(3.0, 80.0),
                      useRadiusInMeter: true,
                      color: (_currentLocation!.recordable
                              ? Colors.blue
                              : Colors.orange)
                          .withOpacity(0.12),
                      borderColor: (_currentLocation!.recordable
                              ? Colors.blue
                              : Colors.orange)
                          .withOpacity(0.55),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // GPS blue dot
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point:  LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
                      width:  60,
                      height: 60,
                      child:  UserLocationMarker(
                        bearing:    _gpsBearing,
                        isEmlidGPS: _locationService.currentProvider == LocationProvider.emlid,
                      ),
                    ),
                  ],
                ),

              // Map measure tool overlays (shared, scratch).
              ...buildMapToolsLayers(),
            ],
          ),

          // ── CENTER CROSSHAIR ───────────────────────────────────────────────
          const Center(
            child: IgnorePointer(
              child: Icon(Icons.location_searching, size: 40, color: Colors.black87),
            ),
          ),

          // ── TOP OVERLAY: back + title + OSM status ─────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    _OverlayBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTitleChip()),
                    const SizedBox(width: 8),
                    _OverlayBtn(
                      icon:  _osmFilePath != null ? Icons.storage_rounded : Icons.storage_outlined,
                      color: _osmFilePath != null ? Colors.greenAccent.shade400 : Colors.white,
                      onTap: showOsmManagementSheet,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── COORDINATES chip / InstructionBar / Calculating chip ───────────
          // Shown just below the top overlay row
          Positioned(
            top:   mq.padding.top + 56,
            left:  0,
            right: 0,
            child: _isNavigating
                ? InstructionBar(
                    instruction:    _currentInstruction,
                    distanceToNext: _distToNext,
                    following:      _followingInstruction,
                    isOffRoute:     _isOffRoute,
                  )
                : _isCalculating
                    ? Center(child: _buildCalculatingChip())
                    : Center(child: _buildCoordinatesChip()),
          ),

          // ── LEFT FABs (bottom-left column) ────────────────────────────────

          // My Location
          Positioned(
            bottom: navBarH + 16,
            left:   16,
            child: FloatingActionButton(
              heroTag:         'nmapUserLocation',
              mini:            true,
              backgroundColor: Colors.white,
              elevation:       6,
              onPressed: () {
                if (_currentLocation != null) {
                  _mapController.move(
                    LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
                    _mapController.camera.zoom, // preserve current zoom, never zoom out
                  );
                } else {
                  _showSnackBar('Location not available');
                }
              },
              child: const Icon(Icons.my_location, color: AppTheme.primaryColor),
            ),
          ),

          // Export
          Positioned(
            bottom: navBarH + 76,
            left:   16,
            child: FloatingActionButton(
              heroTag:         'nmapExport',
              mini:            true,
              backgroundColor: Colors.white,
              elevation:       6,
              onPressed:       _showExportDialog,
              child: const Icon(Icons.ios_share, color: Colors.deepPurple),
            ),
          ),

          // ── RIGHT CONTROLS — satu kolom responsif (tak saling menumpuk) ──────
          MapControlsColumn(
            bottom: navBarH + 16,
            children: [
              // Map measure tools — paling atas.
              buildMapToolsPanel(),

              // Compass / reset north (needle kustom; disamakan 44px kotak-membulat)
              GestureDetector(
                onTap: () {
                  _mapController.rotate(0);
                  setState(() => _currentBearing = 0);
                },
                child: Container(
                  width:  44,
                  height: 44,
                  decoration: BoxDecoration(
                    color:  Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 3))],
                  ),
                  child: Transform.rotate(
                    angle: -_currentBearing * (math.pi / 180),
                    child: CustomPaint(size: const Size(44, 44), painter: _CompassPainter()),
                  ),
                ),
              ),

              // Layers panel (badge = jumlah layer aktif)
              MapToolButton(
                tooltip: 'GeoJSON Layers',
                icon: Icons.layers_outlined,
                active: _layers.any((l) => l.isActive),
                activeColor: Colors.teal,
                iconColor: Colors.teal,
                onPressed: _showLayersPanel,
                badge: _layers.any((l) => l.isActive)
                    ? Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                        child: Center(
                          child: Text(
                            '${_layers.where((l) => l.isActive).length}',
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                    : null,
              ),

              // Basemap selector
              MapToolButton(
                tooltip: 'Change Basemap',
                icon: Icons.map_outlined,
                onPressed: _showBasemapSelector,
              ),
            ],
          ),

          // ── ROUTE CONTROLS (Start / Stop / Clear) ─────────────────────────
          _buildRouteControls(),

          // ── PROPERTIES POPUP ──────────────────────────────────────────────
          _buildPropertiesPopup(),

          // ── OSM IMPORT OVERLAY ────────────────────────────────────────────
          if (isImportingOsm)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Importing routing data...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── ROUTER INITIALIZING BADGE (top-right, subtle) ─────────────────
          if (_isInitializingRouter)
            Positioned(
              top:   mq.padding.top + 56 + 48,
              left:  0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color:        Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 8),
                      Text('Preparing routing engine...', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),

        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Frosted-glass overlay button (back / OSM status)
// ═══════════════════════════════════════════════════════════

class _OverlayBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;

  const _OverlayBtn({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color:        Colors.black.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap:        onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child:   Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Compass Painter
// ═══════════════════════════════════════════════════════════

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;

    final northPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    final northPath  = Path()
      ..moveTo(cx, cy - r * 0.68)
      ..lineTo(cx - r * 0.18, cy)
      ..lineTo(cx, cy - r * 0.12)
      ..lineTo(cx + r * 0.18, cy)
      ..close();
    canvas.drawPath(northPath, northPaint);

    final southPaint = Paint()..color = Colors.grey.shade400..style = PaintingStyle.fill;
    final southPath  = Path()
      ..moveTo(cx, cy + r * 0.68)
      ..lineTo(cx - r * 0.18, cy)
      ..lineTo(cx, cy + r * 0.12)
      ..lineTo(cx + r * 0.18, cy)
      ..close();
    canvas.drawPath(southPath, southPaint);

    canvas.drawCircle(Offset(cx, cy), r * 0.12, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx, cy), r * 0.12, Paint()..color = Colors.grey.shade400..style = PaintingStyle.stroke..strokeWidth = 1);

    final tp = TextPainter(
      text: const TextSpan(text: 'N', style: TextStyle(color: Colors.red, fontSize: 8, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - r * 0.68 - tp.height - 1));
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════
// Layers Panel Sheet
// ═══════════════════════════════════════════════════════════

class _LayersPanelSheet extends StatefulWidget {
  final List<LayerModel> layers;
  final Future<void> Function(LayerModel, bool) onToggle;

  const _LayersPanelSheet({required this.layers, required this.onToggle});

  @override
  State<_LayersPanelSheet> createState() => _LayersPanelSheetState();
}

class _LayersPanelSheetState extends State<_LayersPanelSheet> {
  late List<LayerModel> _layers;
  final Map<String, bool> _loading = {};

  @override
  void initState() {
    super.initState();
    _layers = List.from(widget.layers);
  }

  Future<void> _toggle(LayerModel layer, bool value) async {
    setState(() => _loading[layer.id] = true);
    await widget.onToggle(layer, value);
    setState(() {
      _loading.remove(layer.id);
      final idx = _layers.indexWhere((l) => l.id == layer.id);
      if (idx >= 0) _layers[idx] = _layers[idx].copyWith(isActive: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      maxChildSize:     0.85,
      minChildSize:     0.25,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color:        AppTheme.scaffoldBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width:  40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.layers_outlined, color: Colors.teal, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('GeoJSON Layers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        Text('${_layers.where((l) => l.isActive).length} of ${_layers.length} active',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _layers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.layers_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text('No layers available', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller:       scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount:        _layers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                      itemBuilder: (_, i) {
                        final layer     = _layers[i];
                        final isLoading = _loading[layer.id] == true;
                        final color     = layer.style.fillColor;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          leading: Container(
                            width:  40, height: 40,
                            decoration: BoxDecoration(
                              color:        color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border:       Border.all(color: color.withValues(alpha: 0.5), width: 2),
                            ),
                            child: Icon(layer.geometryIcon, color: color, size: 20),
                          ),
                          title: Text(layer.name,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                  color: layer.isActive ? Colors.black87 : Colors.grey[500])),
                          subtitle: Text(layer.geometryType.toUpperCase(),
                              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                          trailing: isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal))
                              : Switch(
                                  value:                 layer.isActive,
                                  activeColor:           Colors.teal,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onChanged:             (v) => _toggle(layer, v),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Basemap Selector Sheet
// ═══════════════════════════════════════════════════════════

class _BasemapSelectorSheet extends StatefulWidget {
  final Basemap?           currentBasemap;
  final Function(Basemap)  onBasemapSelected;

  const _BasemapSelectorSheet({required this.currentBasemap, required this.onBasemapSelected});

  @override
  State<_BasemapSelectorSheet> createState() => _BasemapSelectorSheetState();
}

class _BasemapSelectorSheetState extends State<_BasemapSelectorSheet> {
  final BasemapService _basemapService = BasemapService();
  List<Basemap> _basemaps  = [];
  bool          _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBasemaps();
  }

  Future<void> _loadBasemaps() async {
    final basemaps = await _basemapService.getBasemaps();
    setState(() { _basemaps = basemaps; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color:        AppTheme.scaffoldBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize:      MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Select Basemap', style: Theme.of(context).textTheme.titleLarge),
                TextButton.icon(
                  icon:  const Icon(Icons.settings),
                  label: const Text('Manage'),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const BasemapManagementScreen()),
                    ).then((_) => _loadBasemaps());
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount:  _basemaps.length,
                  itemBuilder: (context, index) {
                    final basemap    = _basemaps[index];
                    final isSelected = widget.currentBasemap?.id == basemap.id;
                    return ListTile(
                      leading:  Icon(Icons.map, color: isSelected ? AppTheme.primaryColor : Colors.grey),
                      title:    Text(basemap.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text(basemap.type == BasemapType.builtin ? 'Built-in' : 'Custom', style: const TextStyle(fontSize: 12)),
                      trailing: isSelected ? Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                      onTap: () {
                        widget.onBasemapSelected(basemap);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
