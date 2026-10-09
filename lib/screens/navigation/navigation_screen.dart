import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../../widgets/map/compass_button.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoform_app/config/api_config.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../models/basemap_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/layer_model.dart';
import '../../models/project_model.dart';
import '../../models/route_result.dart';
import '../../services/basemap_service.dart';
import '../../services/database_service.dart';
import '../../services/layer_service.dart';
import '../../services/location_service_v2.dart';
import '../../services/routing_service.dart';
import '../../services/settings_service.dart';
import '../../mixins/routing_data_manager.dart';
import '../../mixins/map_tools_host.dart';
import '../../widgets/map/map_controls_column.dart';
import '../../widgets/map/map_tool_button.dart';
import '../../widgets/map/road_network_layer.dart';
import '../../widgets/map/basemap_layers.dart';
import '../../widgets/map/project_feature_layers.dart';
import '../../services/basemap/pdf_overlay_controller.dart';
import '../../theme/app_theme.dart';
import '../basemap/basemap_management_screen.dart';
import '../data_collection/widgets/user_location_marker.dart';
import 'widgets/instruction_bar.dart';
import 'widgets/step_list_sheet.dart';
import '../../utils/ui_feedback.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin,
        RoutingDataManager<NavigationScreen>, MapToolsHost<NavigationScreen> {

  // ─── Services ──────────────────────────────────────────────────────────────
  final _locationService  = LocationServiceV2();
  final _basemapService   = BasemapService();
  final _databaseService  = DatabaseService();
  final _layerService     = LayerService();
  final _routingService   = RoutingService();
  final _settingsService  = SettingsService();
  final _mapController    = MapController();

  /// Alat ukur menggeser peta ini ke titik yang koordinatnya diketik.
  @override
  MapController? get mapToolsMapController => _mapController;
  late final PdfOverlayController _pdfOverlay;

  // ─── GPS ───────────────────────────────────────────────────────────────────
  StreamSubscription<GeoPoint>? _gpsSub;
  GeoPoint? _currentGps;
  double    _gpsBearing        = 0.0; // device compass → UserLocationMarker
  StreamSubscription<CompassEvent>? _compassSub;
  DateTime? _lastCompassUpdate;

  // Smooth marker animation
  late AnimationController _markerAnim;
  LatLng? _markerBegin;
  LatLng? _markerTarget;

  // ─── Map ───────────────────────────────────────────────────────────────────
  Basemap? _selectedBasemap;
  bool     _hasInitialZoom    = false;
  LatLng   _centerCoordinates = const LatLng(-1.0, 113.0);

  // ─── Layers ────────────────────────────────────────────────────────────────
  List<LayerModel>                  _layers     = [];
  Map<String, Map<String, dynamic>> _layerCache = {};

  // ─── Projects & data ───────────────────────────────────────────────────────
  List<Project> _projects       = [];
  Project?      _selectedProject;
  List<GeoData> _projectData    = [];

  // ─── Routing ───────────────────────────────────────────────────────────────
  RouteResult?       _routeResult;
  LatLng?            _destinationPoint;
  SnappedResult?     _snapped;
  int                _currentSegment  = 0;
  String             _activeProfile   = 'car_recommended'; // car | car_recommended | foot
  RouteInstruction?  _currentInstruction;   // upcoming maneuver (shown to user)
  RouteInstruction?  _followingInstruction; // maneuver after the upcoming one
  double             _distToNext      = 0;
  bool               _isNavigating    = false;
  bool               _isFollowingUser = false; // auto-center map on GPS updates
  bool               _headingUp       = false; // peta berputar mengikuti arah jalan
  double             _lastAutoRotation = 0.0;  // rotasi terakhir yang diterapkan heading-up
  bool               _isOffRoute      = false;
  bool               _isCalculating   = false;
  Timer?             _recalcDebounce;
  final List<TrackPoint> _uTurnWindow = [];

  // ─── OSM ───────────────────────────────────────────────────────────────────
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

  // ─── Location init ─────────────────────────────────────────────────────────
  bool    _isLoadingLocation   = false;

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _markerAnim = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() { if (mounted) setState(() {}); });
    // Overlay PDF disiapkan sekali per ganti basemap (bukan di build).
    _pdfOverlay = PdfOverlayController(onProblem: _showBasemapProblem)
      ..addListener(_onPdfOverlayChanged);
    _initCompass(); // Start compass independently — must not wait for GPS
    _init();
  }

  void _onPdfOverlayChanged() {
    if (mounted) setState(() {});
  }

  void _showBasemapProblem(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.orange,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _init() async {
    await _settingsService.initialize();
    await Future.wait([
      _loadBasemap(),
      _loadActiveLayers(),
      _loadProjects(),
      _loadOsmState(),
    ]);
    await loadRoadLayerState(); // basemap jaringan jalan (setelah osm state siap)
    await _startGps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pdfOverlay
      ..removeListener(_onPdfOverlayChanged)
      ..dispose();
    _gpsSub?.cancel();
    _compassSub?.cancel();
    _recalcDebounce?.cancel();
    _markerAnim.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INITIALIZATION HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadBasemap() async {
    final b = await _basemapService.getSelectedBasemap();
    if (!mounted) return;
    setState(() => _selectedBasemap = b);
    _pdfOverlay.show(b);
  }

  Future<void> _loadActiveLayers() async {
    final layers = await _layerService.loadLayers();
    final cache  = <String, Map<String, dynamic>>{};
    for (final l in layers) {
      if (l.isActive) {
        try {
          final gj = await _layerService.readGeoJson(l.filePath);
          if (gj != null) cache[l.id] = gj;
        } catch (_) {}
      }
    }
    if (mounted) setState(() { _layers = layers; _layerCache = cache; });
  }

  Future<void> _toggleLayerActive(LayerModel layer, bool active) async {
    await _layerService.toggleLayer(layer.id, active);
    await _loadActiveLayers();
  }

  Future<void> _loadProjects() async {
    final projs = await _databaseService.loadProjects();
    if (mounted) setState(() => _projects = projs);
  }

  Future<void> _loadOsmState() async {
    final path = await _routingService.getOsmFilePath();
    if (!mounted) return;
    setState(() => _osmFilePath = path);
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
      if (!ok) _showSnackBar('⚠️ Routing engine failed to load. Re-import routing file.');
    } catch (e) {
      if (mounted) _showSnackBar(loggedErrorMessage('Could not start offline routing', e, tag: 'NAV'));
    } finally {
      if (mounted) setState(() => _isInitializingRouter = false);
    }
  }

  Future<void> _startGps() async {
    if (mounted) setState(() => _isLoadingLocation = true);

    try {
      // 1. Permission check
      final hasPermission = await _locationService.checkAndRequestPermission();
      if (!hasPermission) {
        if (mounted) _showSnackBar('⚠️ Location permission required for navigation');
        return;
      }

      // 2. Initialize service + load provider settings (phone GPS vs Emlid)
      await _locationService.initialize();
      await _locationService.loadLocationSettings();

      // 3. Start persistent stream
      await _locationService.startForegroundTracking();
      _gpsSub?.cancel();
      _gpsSub = _locationService.trackLocation().listen(_onGpsUpdate);

      // 4. One-shot for immediate map centering
      final loc = await _locationService.getCurrentLocation();
      if (loc != null && mounted && !_hasInitialZoom) {
        _hasInitialZoom = true;
        final ll = LatLng(loc.latitude, loc.longitude);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try { _mapController.move(ll, 16.0); } catch (_) {}
        });
        setState(() => _currentGps = loc);
      }
    } catch (e) {
      if (mounted) _showSnackBar(loggedErrorMessage('Could not get your location', e, tag: 'NAV'));
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _initCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      final now = DateTime.now();
      if (_lastCompassUpdate != null &&
          now.difference(_lastCompassUpdate!).inMilliseconds < 100) return;
      _lastCompassUpdate = now;
      if (event.heading != null && mounted) {
        setState(() => _gpsBearing = event.heading!);
        if (_headingUp) _applyHeadingUp(event.heading!);
      }
    });
  }

  /// Heading-up: putar peta agar arah jalan (heading) menghadap ke atas.
  /// Throttle perubahan kecil (<2°) agar tidak jitter; jarum utara (CompassButton)
  /// otomatis mengikuti karena terikat rotasi peta.
  void _applyHeadingUp(double heading) {
    final double? target;
    try {
      target = headingUpRotation(heading, _mapController.camera.rotation);
    } catch (_) {
      return;
    }
    if (target == null) return;
    try {
      _mapController.rotate(target);
      _lastAutoRotation = target;
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GPS UPDATES
  // ─────────────────────────────────────────────────────────────────────────

  void _onGpsUpdate(GeoPoint point) {
    if (!mounted) return;

    final newLatLng = LatLng(point.latitude, point.longitude);

    // Animate marker
    _markerBegin  = _markerTarget ?? newLatLng;
    _markerTarget = newLatLng;
    _markerAnim..reset()..forward();

    // Auto-zoom on first fix
    if (!_hasInitialZoom) {
      _hasInitialZoom = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try { _mapController.move(newLatLng, 16.0); } catch (_) {}
      });
    }

    // Auto-center map while following user (navigation follow mode)
    if (_isNavigating && _isFollowingUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isFollowingUser) {
          try {
            _mapController.move(newLatLng, _mapController.camera.zoom);
          } catch (_) {}
        }
      });
    }

    // U-turn window
    _uTurnWindow.add(TrackPoint(newLatLng, point.speed));
    if (_uTurnWindow.length > 20) _uTurnWindow.removeAt(0);

    // Routing logic while navigating
    if (_isNavigating && _routeResult != null) {
      final snap = _routingService.snapToRoute(
        newLatLng,
        _routeResult!.latLngs,
        point.accuracy ?? 25.0,
      );
      _currentSegment = snap.segmentIndex;

      // Show the UPCOMING maneuver (ahead of the current segment) so the
      // prompt appears BEFORE the turn — Google-style — instead of the
      // maneuver we are already on.
      final instr = _routingService.upcomingInstruction(
        _currentSegment, _routeResult!.instructions,
      );
      final following = _routingService.followingInstruction(
        _currentSegment, _routeResult!.instructions,
      );
      final distNext = _routingService.distanceToNextInstruction(
        snap.point, _currentSegment, _routeResult!.instructions, _routeResult!.points,
      );

      // U-turn check
      if (_routingService.detectUTurn(_uTurnWindow)) {
        _showSnackBar('⚠️ Possible U-turn detected');
      }

      // Off-route → debounced recalculate (fitBounds: false — don't zoom out
      // while navigating; follow mode will keep user centered)
      if (snap.isOffRoute && !_isOffRoute) {
        _recalcDebounce?.cancel();
        _recalcDebounce = Timer(const Duration(seconds: 3), () {
          if (_isNavigating && _destinationPoint != null) {
            _calculateRoute(to: _destinationPoint!, fitBounds: false);
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
        _currentGps         = point;
        _snapped            = snap;
        _isOffRoute         = snap.isOffRoute;
        _currentInstruction   = instr;
        _followingInstruction = following;
        _distToNext           = distNext;
      });
    } else {
      setState(() {
        _currentGps = point;
        _snapped    = null;
        _isOffRoute = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ROUTING
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _calculateRoute({
    required LatLng to,
    String? profile,                // null → reuse the last chosen profile
    bool fitBounds  = true, // false when recalculating during active navigation
  }) async {
    if (!isRoutingAvailable) { showRoutingUnavailableDialog(); return; }
    if (_isInitializingRouter) {
      _showSnackBar('⏳ Routing engine is preparing, please wait...');
      return;
    }
    final gps = _currentGps;
    if (gps == null) { _showSnackBar('⚠️ GPS not available yet'); return; }
    if (_osmFilePath == null) { showOsmMissingDialog(); return; }

    // Persist the active profile so off-route recalculation keeps the same
    // vehicle + mode (car / car_recommended / foot) instead of reverting to car.
    final activeProfile = profile ?? _activeProfile;
    _activeProfile = activeProfile;

    setState(() { _isCalculating = true; _isOffRoute = false; });
    try {
      final from   = LatLng(gps.latitude, gps.longitude);
      final result = await _routingService.calculateRoute(
        from: from, to: to, profile: activeProfile,
      );
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
      // Only zoom to fit the full route when explicitly requested —
      // never during active navigation (would zoom out and break follow mode)
      if (fitBounds) _fitRouteBounds(result.latLngs);
    } catch (e) {
      if (mounted) _showSnackBar(loggedErrorMessage('Could not calculate the route', e, tag: 'NAV'));
    } finally {
      if (mounted) setState(() => _isCalculating = false);
    }
  }

  String get _profileLabel {
    switch (_activeProfile) {
      case 'car_recommended': return 'Recommended';
      case 'foot':            return 'Walking';
      default:                return 'Fastest';
    }
  }

  void _showStepList() {
    final route = _routeResult;
    if (route == null) return;
    showStepListSheet(context, route: route, currentSegment: _currentSegment);
  }

  void _startNavigation() {
    if (_routeResult == null) return;
    setState(() {
      _isNavigating    = true;
      _isFollowingUser = true; // engage follow mode
      _uTurnWindow.clear();
    });
    _showSnackBar('▶️ Navigation started');
  }

  void _stopNavigation() {
    _recalcDebounce?.cancel();
    setState(() {
      _isNavigating       = false;
      _isFollowingUser    = false; // disengage follow mode
      _isOffRoute         = false;
      _currentInstruction = null;
      _followingInstruction = null;
    });
  }

  void _clearRoute() {
    _stopNavigation();
    setState(() {
      _routeResult      = null;
      _destinationPoint = null;
      _snapped          = null;
    });
  }

  void _onArrived() {
    _stopNavigation();
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
            onPressed: () { Navigator.pop(context); _clearRoute(); },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PROJECT DATA
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _selectProject(Project? project) async {
    setState(() { _selectedProject = project; _projectData = []; });
    if (project == null) return;
    final data = await _databaseService.loadGeoData(project.id);
    if (mounted) setState(() => _projectData = data);
  }

  void _showProjectSelectorSheet() {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProjectSelectorSheet(
        projects:        _projects,
        selectedProject: _selectedProject,
        onSelected:      (p) { Navigator.pop(context); _selectProject(p); },
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  // MAP HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Core FlutterMap widget shared between normal and tilted views.
  Widget _buildFlutterMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(-1.0, 113.0),
        initialZoom:   5.0,
        onTap:         (pos, latlng) { handleMapToolsTap(latlng); },
        onLongPress:   _onMapLongPress,
        onPositionChanged: (pos, hasGesture) {
          final c = pos.center;
          if (_centerCoordinates.latitude  != c.latitude ||
              _centerCoordinates.longitude != c.longitude) {
            if (mounted) setState(() => _centerCoordinates = c);
          }
          if (hasGesture) {
            // User is manually panning/zooming — disengage follow mode
            if (_isFollowingUser && mounted) {
              setState(() => _isFollowingUser = false);
            }
            // Manual rotate → matikan heading-up agar tidak berkejaran
            if (_headingUp && mounted) {
              final r = _mapController.camera.rotation;
              if (headingUpOverridden(_lastAutoRotation, r)) {
                setState(() => _headingUp = false);
              }
            }
          }
        },
      ),
      children: [
        // Basemap
        // Tanpa I/O: overlay PDF disiapkan _pdfOverlay saat ganti basemap.
        if (_selectedBasemap != null)
          ...buildBasemapLayers(
            _selectedBasemap!,
            overlay: _pdfOverlay.spec,
            fallback: _osmFallback,
          )
        else
          TileLayer(
            urlTemplate:          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: ApiConfig.bundleName,
          ),

        // Basemap jaringan jalan (raster on-device, lazy; zoom>10; toggle) —
        // di atas basemap, di bawah data lain.
        RoadNetworkLayer(provider: roadTileProvider, visible: roadLayerOn),

        // GeoJSON layers
        ..._buildGeoJsonLayers(),

        // Project data (with SettingsService styling)
        ..._buildProjectDataLayers(),

        // Route polyline
        if (_routeResult != null)
          PolylineLayer(polylines: _buildRoutePolylines()),

        // Destination marker
        if (_destinationPoint != null)
          MarkerLayer(markers: [_buildDestinationMarker()]),

        // Snapped position dot (active navigation only)
        if (_snapped != null && _isNavigating)
          MarkerLayer(markers: [_buildSnappedMarker()]),

        // Accuracy ring — radius = akurasi (m); biru = fix bagus, amber = acquiring.
        if (_animatedMarker != null && _currentGps != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: _animatedMarker!,
                radius: (_currentGps!.accuracy ?? 15).clamp(3.0, 80.0),
                useRadiusInMeter: true,
                color: (_currentGps!.recordable ? Colors.blue : Colors.orange)
                    .withOpacity(0.12),
                borderColor:
                    (_currentGps!.recordable ? Colors.blue : Colors.orange)
                        .withOpacity(0.55),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),

        // GPS blue dot (smooth animated)
        if (_animatedMarker != null)
          MarkerLayer(markers: [
            Marker(
              point:  _animatedMarker!,
              width:  60,
              height: 60,
              child:  UserLocationMarker(bearing: _gpsBearing),
            ),
          ]),

        // Map measure tool overlays (shared, scratch).
        ...buildMapToolsLayers(),

        // Overlay PDF sedang di-decode (ganti basemap).
        if (_pdfOverlay.loading) const PdfOverlayLoadingChip(),
      ],
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

  void _recenterOnGps() {
    final gps = _currentGps;
    if (gps == null) { _showSnackBar('Location not available'); return; }
    _mapController.move(
      LatLng(gps.latitude, gps.longitude),
      _mapController.camera.zoom, // preserve current zoom, never zoom out
    );
    // Re-engage follow mode if navigation is active
    if (_isNavigating && !_isFollowingUser) {
      setState(() => _isFollowingUser = true);
    }
  }

  void _showLayersPanel() {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LayersPanelSheet(
        layers:   _layers,
        onToggle: _toggleLayerActive,
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
        currentBasemap:    _selectedBasemap,
        onBasemapSelected: (basemap) async {
          await _basemapService.setSelectedBasemap(basemap.id);
          await _loadBasemap();
          // PDF di luar layar → kamera ke PDF; matikan follow agar GPS tak
          // langsung menarik kamera kembali (sama seperti geser manual).
          final b = _selectedBasemap;
          if (mounted &&
              b != null &&
              fitCameraToPdfIfOffscreen(_mapController, b)) {
            setState(() => _isFollowingUser = false);
          }
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ANIMATED MARKER
  // ─────────────────────────────────────────────────────────────────────────

  LatLng? get _animatedMarker {
    final t = _markerTarget;
    if (t == null) return null;
    final b = _markerBegin ?? t;
    final v = Curves.easeOut.transform(_markerAnim.value);
    return LatLng(
      ui.lerpDouble(b.latitude,  t.latitude,  v)!,
      ui.lerpDouble(b.longitude, t.longitude, v)!,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq      = MediaQuery.of(context);
    final navBarH = mq.viewPadding.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody:             true,
      backgroundColor:        AppTheme.scaffoldBackground,
      body: Stack(
        children: [

          // ── MAP ─────────────────────────────────────────────────────────
          _buildFlutterMap(),

          // ── CENTER CROSSHAIR ─────────────────────────────────────────────
          const Center(
            child: IgnorePointer(
              child: Icon(Icons.location_searching, size: 40, color: Colors.black87),
            ),
          ),

          // ── TOP OVERLAY: back + title chip + OSM status ──────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    _OverlayBtn(
                      icon:  Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTitleChip()),
                    const SizedBox(width: 8),
                    _OverlayBtn(
                      icon:  _osmFilePath != null
                          ? Icons.storage_rounded
                          : Icons.storage_outlined,
                      color: _osmFilePath != null
                          ? Colors.greenAccent.shade400
                          : Colors.white,
                      onTap: showOsmManagementSheet,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── SECOND ROW: InstructionBar / Calculating chip / Coordinates ───
          Positioned(
            top:  mq.padding.top + 56,
            left: 0, right: 0,
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

          // ── LEFT FABs ─────────────────────────────────────────────────────

          // My Location / Follow mode toggle
          Positioned(
            bottom: navBarH + 16,
            left:   16,
            child: FloatingActionButton(
              heroTag:         'navMyLocation',
              mini:            true,
              backgroundColor: _isNavigating && _isFollowingUser
                  ? AppTheme.primaryGreen   // follow mode ON → green
                  : Colors.white,
              elevation:       6,
              tooltip: _isNavigating && _isFollowingUser
                  ? 'Following (tap to unlock)'
                  : 'My Location',
              onPressed: _recenterOnGps,
              child: Icon(
                _isNavigating && _isFollowingUser
                    ? Icons.navigation_rounded  // active follow
                    : Icons.my_location,
                color: _isNavigating && _isFollowingUser
                    ? Colors.white
                    : AppTheme.primaryColor,
              ),
            ),
          ),

          // Project Data selector
          Positioned(
            bottom: navBarH + 76,
            left:   16,
            child: FloatingActionButton(
              heroTag:         'navProject',
              mini:            true,
              backgroundColor: _selectedProject != null
                  ? AppTheme.primaryGreen
                  : Colors.white,
              elevation:       6,
              tooltip:         'Project Data',
              onPressed:       _showProjectSelectorSheet,
              child: Icon(
                Icons.folder_open_rounded,
                color: _selectedProject != null
                    ? Colors.white
                    : AppTheme.primaryGreen,
              ),
            ),
          ),

          // ── RIGHT CONTROLS — satu kolom responsif (tak saling menumpuk) ──────
          MapControlsColumn(
            bottom: navBarH + 16,
            children: [
              // Map measure tools (launcher + live readout) — paling atas.
              buildMapToolsPanel(),

              // Heading-up toggle — peta berputar mengikuti arah jalan
              MapToolButton(
                tooltip: 'Heading up',
                icon: Icons.explore,
                active: _headingUp,
                onPressed: () {
                  setState(() => _headingUp = !_headingUp);
                  if (!_headingUp) _mapController.rotate(0); // kembali north-up
                },
              ),

              // Compass — tap to reset north (animated); also exits heading-up
              CompassButton(
                mapController: _mapController,
                size: 44,
                onResetToNorth: () {
                  if (_headingUp) setState(() => _headingUp = false);
                },
              ),

              // Layers with active-count badge
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
                        decoration: const BoxDecoration(
                            color: Colors.orange, shape: BoxShape.circle),
                        child: Center(
                          child: Text(
                            '${_layers.where((l) => l.isActive).length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold),
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

              // Basemap jaringan jalan (on/off) — hanya berguna bila ada data.
              MapToolButton(
                tooltip: 'Road network',
                icon: Icons.alt_route,
                active: roadLayerOn && roadTileProvider != null,
                onPressed: toggleRoadLayer,
              ),
            ],
          ),

          // ── ROUTE CONTROLS (Start / Stop / Clear) ────────────────────────
          _buildRouteControls(),

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

          // ── LOCATION LOADING BADGE ───────────────────────────────────────
          if (_isLoadingLocation)
            Positioned(
              top:  mq.padding.top + 56 + 48,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color:        Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 8),
                      Text('Getting your location...',
                          style: TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),

          // ── ROUTER INITIALIZING BADGE ─────────────────────────────────────
          if (_isInitializingRouter)
            Positioned(
              top:  mq.padding.top + 56 + 48,
              left: 0, right: 0,
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
                      SizedBox(
                        width:  12, height: 12,
                        child:  CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 8),
                      Text('Preparing routing engine...',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),

        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAP LONG PRESS → ROUTE DIALOG
  // ─────────────────────────────────────────────────────────────────────────

  void _onMapLongPress(TapPosition tap, LatLng point) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RouteTargetSheet(
        point:       point,
        hasOsm:      _osmFilePath != null,
        onRoute: (profile) {
          Navigator.pop(context);
          _calculateRoute(to: point, profile: profile);
        },
        onImportOsm: () {
          Navigator.pop(context);
          importOsmFile();
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI CHIPS & ROUTE CONTROLS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTitleChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:        Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: const Text(
        'Navigation',
        style: TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

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
            '${_centerCoordinates.latitude.toStringAsFixed(6)}, '
            '${_centerCoordinates.longitude.toStringAsFixed(6)}',
            style: const TextStyle(
              fontSize:   12,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
              color:      Colors.white,
            ),
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
          SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          SizedBox(width: 10),
          Text('Calculating route...',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// Floating route-info panel: shows route distance/time + Start/Stop/Clear buttons.
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
                mainAxisSize:       MainAxisSize.min,
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
                    '$_profileLabel  •  ${_routeResult!.formattedDistance}  •  ${_routeResult!.formattedTime}',
                    style: TextStyle(
                      fontSize: 11,
                      color:    _isNavigating
                          ? Colors.white70
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            // Directions / step list button (always available with a route)
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
            // Start button (not yet navigating)
            if (!_isNavigating) ...[
              GestureDetector(
                onTap: _startNavigation,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:        AppTheme.primaryGreen,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.navigation_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('Start',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Stop button (while navigating)
            if (_isNavigating)
              GestureDetector(
                onTap: _stopNavigation,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:        Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_circle_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('Stop',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              )
            // Clear route (X) — shown when not navigating
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
                  child: Icon(Icons.close,
                      color: Colors.red.shade400, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LAYER BUILDERS
  // ─────────────────────────────────────────────────────────────────────────

  TileLayer _osmFallback() => TileLayer(
        urlTemplate:          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: ApiConfig.bundleName,
      );

  List<Widget> _buildGeoJsonLayers() {
    final widgets = <Widget>[];
    for (final layer in _layers) {
      if (!layer.isActive) continue;
      final gj = _layerCache[layer.id];
      if (gj == null) continue;

      final features  = gj['features'] as List<dynamic>? ?? [];
      final polylines = <Polyline>[];
      final polygons  = <Polygon>[];
      final markers   = <Marker>[];

      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final geom    = feature['geometry'] as Map<String, dynamic>?;
        if (geom == null) continue;
        final type    = geom['type'] as String? ?? '';

        switch (type) {
          case 'Point':
            final c = geom['coordinates'] as List;
            markers.add(_layerPointMarker(
              LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
              layer,
            ));
            break;
          case 'MultiPoint':
            for (final c in geom['coordinates'] as List) {
              final coords = c as List;
              markers.add(_layerPointMarker(
                LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
                layer,
              ));
            }
            break;
          case 'LineString':
            final pts = _coordsToLatLng(geom['coordinates'] as List);
            if (pts.length >= 2) {
              polylines.add(Polyline(
                points:      pts,
                color:       layer.style.strokeColor
                    .withValues(alpha: layer.style.fillOpacity),
                strokeWidth: layer.style.strokeWidth,
              ));
            }
            break;
          case 'MultiLineString':
            for (final line in geom['coordinates'] as List) {
              final pts = _coordsToLatLng(line as List);
              if (pts.length >= 2) {
                polylines.add(Polyline(
                  points:      pts,
                  color:       layer.style.strokeColor
                      .withValues(alpha: layer.style.fillOpacity),
                  strokeWidth: layer.style.strokeWidth,
                ));
              }
            }
            break;
          case 'Polygon':
            final rings = geom['coordinates'] as List;
            final outer = _coordsToLatLng(rings[0] as List);
            if (outer.length >= 3) {
              polygons.add(Polygon(
                points:            outer,
                color:             layer.style.fillColor
                    .withValues(alpha: layer.style.fillOpacity),
                borderColor:       layer.style.strokeColor,
                borderStrokeWidth: layer.style.strokeWidth,
              ));
            }
            break;
          case 'MultiPolygon':
            for (final poly in geom['coordinates'] as List) {
              final rings = poly as List;
              final outer = _coordsToLatLng(rings[0] as List);
              if (outer.length >= 3) {
                polygons.add(Polygon(
                  points:            outer,
                  color:             layer.style.fillColor
                      .withValues(alpha: layer.style.fillOpacity),
                  borderColor:       layer.style.strokeColor,
                  borderStrokeWidth: layer.style.strokeWidth,
                ));
              }
            }
            break;
        }
      }

      if (polylines.isNotEmpty) widgets.add(PolylineLayer(polylines: polylines));
      if (polygons.isNotEmpty)  widgets.add(PolygonLayer(polygons: polygons));
      if (markers.isNotEmpty)   widgets.add(MarkerLayer(markers: markers));
    }
    return widgets;
  }

  /// Render project data using SettingsService colors — identical to DataCollectionScreen.
  List<Widget> _buildProjectDataLayers() {
    if (_projectData.isEmpty) return [];

    final s         = _settingsService.settings;
    final markers   = <Marker>[];
    final polylines = <Polyline>[];
    final polygons  = <Polygon>[];

    for (final geoData in _projectData) {
      if (geoData.points.isEmpty) continue;
      final pts = geoData.points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();

      final geomType = _selectedProject?.geometryType;

      if (geomType == GeometryType.point || pts.length == 1) {
        // ── Point marker ─────────────────────────────────────────────────
        // Style record, atau default Settings (tampil seperti sebelumnya).
        markers.add(featurePointMarker(
          geoData,
          effectiveFeatureStyle(geoData, GeometryType.point, s),
          iconScale: 0.5,
          minIconSize: 0,
          maxIconSize: double.infinity,
        ));
      } else if (geomType == GeometryType.polygon && pts.length >= 3) {
        // ── Polygon ──────────────────────────────────────────────────────
        // Tanpa ikon info di tengah feature (sama dengan peta project).
        polygons.add(featurePolygon(geoData,
            effectiveFeatureStyle(geoData, GeometryType.polygon, s)));
      } else if (pts.length >= 2) {
        // ── Line ─────────────────────────────────────────────────────────
        polylines.add(featurePolyline(geoData,
            effectiveFeatureStyle(geoData, GeometryType.line, s)));
      }
    }

    return [
      if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
      if (polygons.isNotEmpty)  PolygonLayer(polygons: polygons),
      if (markers.isNotEmpty)   MarkerLayer(markers: markers),
    ];
  }

  List<Polyline> _buildRoutePolylines() {
    final route = _routeResult!;
    final all   = route.latLngs;

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
        child:  const Icon(Icons.location_on_rounded,
            color: Colors.red, size: 36),
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

  Marker _layerPointMarker(LatLng pos, LayerModel layer) => Marker(
        point:  pos,
        width:  22,
        height: 22,
        child:  Container(
          decoration: BoxDecoration(
            color:  layer.style.fillColor.withValues(alpha: 0.9),
            shape:  BoxShape.circle,
            border: Border.all(color: layer.style.strokeColor, width: 1.5),
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  List<LatLng> _coordsToLatLng(List coords) => coords
      .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
      .toList();

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frosted-glass overlay button (back / OSM status)
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Route Target Sheet — long-press destination
// ─────────────────────────────────────────────────────────────────────────────

class _RouteTargetSheet extends StatelessWidget {
  final LatLng  point;
  final bool    hasOsm;
  final void Function(String profile) onRoute;
  final VoidCallback onImportOsm;

  const _RouteTargetSheet({
    required this.point,
    required this.hasOsm,
    required this.onRoute,
    required this.onImportOsm,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize:       MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.location_on_rounded, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Text(
              '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Route to this point',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 16),

          if (!hasOsm) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                Icon(Icons.warning_rounded,
                    color: Colors.orange.shade700, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Routing data not imported. Please import a .pbf file first.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onImportOsm,
                icon:  const Icon(Icons.file_open_rounded, size: 16),
                label: const Text('Import Routing Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ] else ...[
            // ── Mobil: pilih mode rute ──
            Text('Car',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: _RouteBtn(
                  icon:  Icons.recommend_rounded,
                  label: 'Recommended',
                  sublabel: 'Prefers main roads',
                  color: AppTheme.primaryGreen,
                  highlighted: true,
                  onTap: () => onRoute('car_recommended'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RouteBtn(
                  icon:  Icons.bolt_rounded,
                  label: 'Fastest',
                  sublabel: 'Shortest travel time',
                  color: AppTheme.darkGreen,
                  onTap: () => onRoute('car'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            // ── Jalan kaki ──
            SizedBox(
              width: double.infinity,
              child: _RouteBtn(
                icon:  Icons.directions_walk_rounded,
                label: 'Walking',
                color: AppTheme.accentGreen,
                onTap: () => onRoute('foot'),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
      ), // Padding
    ); // SafeArea
  }
}

class _RouteBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final String?      sublabel;
  final Color        color;
  final bool         highlighted;
  final VoidCallback onTap;

  const _RouteBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.sublabel,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (sublabel != null) ...[
          const SizedBox(height: 2),
          Text(
            sublabel!,
            style: TextStyle(
                fontSize: 10, color: Colors.white.withValues(alpha: 0.85)),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: highlighted ? 3 : 1,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: highlighted
              ? const BorderSide(color: Colors.white, width: 1.5)
              : BorderSide.none,
        ),
      ),
      child: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Project Selector Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectSelectorSheet extends StatelessWidget {
  final List<Project>              projects;
  final Project?                   selectedProject;
  final void Function(Project?)    onSelected;

  const _ProjectSelectorSheet({
    required this.projects,
    required this.selectedProject,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:        AppTheme.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.folder_open_rounded,
                        color: AppTheme.primaryGreen, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Project Data',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        Text('Display project data on map',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // None option
            ListTile(
              leading: const Icon(Icons.do_not_disturb_rounded,
                  color: Colors.grey),
              title: const Text('— None —',
                  style: TextStyle(fontSize: 13)),
              trailing: selectedProject == null
                  ? const Icon(Icons.check_circle,
                      color: AppTheme.primaryGreen)
                  : null,
              onTap: () => onSelected(null),
            ),
            if (projects.isNotEmpty) const Divider(height: 1, indent: 56),
            // Project list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: projects.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No projects available',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding:    EdgeInsets.zero,
                      itemCount:  projects.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (_, i) {
                        final p          = projects[i];
                        final isSelected = selectedProject?.id == p.id;
                        return ListTile(
                          leading: Icon(
                            Icons.folder_rounded,
                            color: isSelected
                                ? AppTheme.primaryGreen
                                : Colors.grey,
                          ),
                          title: Text(
                            p.name,
                            style: TextStyle(
                              fontSize:   13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : Colors.black87,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle,
                                  color: AppTheme.primaryGreen)
                              : null,
                          onTap: () => onSelected(p),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layers Panel Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LayersPanelSheet extends StatefulWidget {
  final List<LayerModel>                       layers;
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
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:        Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.layers_outlined,
                        color: Colors.teal, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('GeoJSON Layers',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(
                          '${_layers.where((l) => l.isActive).length} of '
                          '${_layers.length} active',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
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
                          Icon(Icons.layers_outlined,
                              size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text('No layers available',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 14)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller:       scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount:        _layers.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (_, i) {
                        final layer     = _layers[i];
                        final isLoading = _loading[layer.id] == true;
                        final color     = layer.style.fillColor;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          leading: Container(
                            width:  40, height: 40,
                            decoration: BoxDecoration(
                              color:        color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border:       Border.all(
                                  color: color.withValues(alpha: 0.5),
                                  width: 2),
                            ),
                            child: Icon(layer.geometryIcon,
                                color: color, size: 20),
                          ),
                          title: Text(
                            layer.name,
                            style: TextStyle(
                              fontSize:   13,
                              fontWeight: FontWeight.w600,
                              color: layer.isActive
                                  ? Colors.black87
                                  : Colors.grey[500],
                            ),
                          ),
                          subtitle: Text(
                            layer.geometryType.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[500]),
                          ),
                          trailing: isLoading
                              ? const SizedBox(
                                  width:  20, height: 20,
                                  child:  CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.teal),
                                )
                              : Switch(
                                  value:                 layer.isActive,
                                  activeColor:           Colors.teal,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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

// ─────────────────────────────────────────────────────────────────────────────
// Basemap Selector Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _BasemapSelectorSheet extends StatefulWidget {
  final Basemap?          currentBasemap;
  final Function(Basemap) onBasemapSelected;

  const _BasemapSelectorSheet({
    required this.currentBasemap,
    required this.onBasemapSelected,
  });

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
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Select Basemap',
                    style: Theme.of(context).textTheme.titleLarge),
                TextButton.icon(
                  icon:  const Icon(Icons.settings),
                  label: const Text('Manage'),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BasemapManagementScreen()),
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
                  itemBuilder: (_, index) {
                    final basemap    = _basemaps[index];
                    final isSelected =
                        widget.currentBasemap?.id == basemap.id;
                    return ListTile(
                      leading: Icon(Icons.map,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.grey),
                      title: Text(
                        basemap.name,
                        style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal),
                      ),
                      subtitle: Text(
                        basemap.type == BasemapType.builtin
                            ? 'Built-in'
                            : 'Custom',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle,
                              color: AppTheme.primaryColor)
                          : null,
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

// ─────────────────────────────────────────────────────────────────────────────
// Compass Painter
// ─────────────────────────────────────────────────────────────────────────────

