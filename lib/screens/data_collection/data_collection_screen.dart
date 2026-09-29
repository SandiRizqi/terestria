import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geoform_app/config/api_config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_compass/flutter_compass.dart';
import '../../widgets/map/compass_button.dart';
import '../../widgets/map/map_controls_column.dart';
import '../../widgets/map/map_tool_button.dart';
import '../../widgets/map/basemap_layers.dart';
import '../../services/basemap/pdf_overlay_controller.dart';
import '../../mixins/map_tools_host.dart';
import '../../models/project_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/basemap_model.dart';
import '../../models/form_field_model.dart';
import '../../services/location_service_v2.dart';
import '../../services/storage_service.dart';
import '../../services/tracking/tracking_engine.dart';
import '../../services/tracking/tracking_session.dart';
import '../../services/tracking/tracking_session_manager.dart';
import '../../services/tracking/session_to_geodata.dart';
import '../../services/basemap_service.dart';
import '../../services/tile_providers/sqlite_cached_tile_provider.dart';
import '../../widgets/dynamic_form.dart';
import '../../widgets/photo_field_widget.dart';
import '../../services/crashlytics_service.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import '../../theme/app_theme.dart';
import 'widgets/collapsible_bottom_controls.dart';
import 'widgets/user_location_marker.dart';
import '../basemap/basemap_selector_sheet.dart';
import '../location/location_provider_screen.dart';
import '../../services/auth_service.dart';
import '../../services/background/permission_service.dart';
import '../../services/settings_service.dart';
import '../project/edit_geo_data_screen.dart';
import '../../widgets/offline_download_dialog.dart';
import '../../utils/lat_lng_bounds.dart' as custom_bounds;
import '../../models/layer_model.dart';
import '../../services/layer_service.dart';
import '../../services/collection_draft_service.dart';
import '../../services/device_health_service.dart';
import '../../services/geometry_validation.dart';
import '../../utils/ui_feedback.dart';
import '../../widgets/readiness/daily_readiness_check.dart';
import '../readiness/field_readiness_screen.dart';
import '../../widgets/collection/gps_status_banners.dart';
import 'package:shared_preferences/shared_preferences.dart';


import '../../utils/app_logger.dart';
enum CollectionMode { tracking, drawing }

class DataCollectionScreen extends StatefulWidget {
  final Project project;

  const DataCollectionScreen({Key? key, required this.project})
      : super(key: key);

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver,
        TickerProviderStateMixin, MapToolsHost<DataCollectionScreen> {
  @override
  bool get wantKeepAlive => true;
  final LocationServiceV2 _locationService = LocationServiceV2();
  final StorageService _storageService = StorageService();
  final BasemapService _basemapService = BasemapService();
  final SettingsService _settingsService = SettingsService();
  final MapController _mapController = MapController();
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  /// Titik mode manual/drawing saat project ini TIDAK punya sesi tracking.
  final List<GeoPoint> _manualPoints = [];

  /// Fix GPS terkini. Notifier (bukan setState) agar update 1 Hz & animasi
  /// marker tak me-rebuild seluruh layar + semua layer peta.
  final ValueNotifier<GeoPoint?> _locationNotifier = ValueNotifier(null);
  GeoPoint? get _currentLocation => _locationNotifier.value;
  set _currentLocation(GeoPoint? value) => _locationNotifier.value = value;

  /// Arah kompas & tengah peta — juga notifier (sensor ±10 Hz / tiap frame geser).
  final ValueNotifier<double> _bearingNotifier = ValueNotifier(0.0);
  final ValueNotifier<LatLng> _centerNotifier =
      ValueNotifier(const LatLng(-6.2088, 106.8456));

  /// Draft titik manual + isian form (bertahan bila app dibunuh saat kamera).
  final CollectionDraftService _draftService = CollectionDraftService();
  Timer? _draftDebounce;
  final DynamicFormController _formController = DynamicFormController();

  /// Layer GeoJSON impor yang sudah dibangun (di-cache; tak bergantung zoom).
  List<Widget> _geoJsonLayerWidgets = const [];
  bool _emlidWasConnected = false;

  // ─── Layar = tampilan atas sesi ────────────────────────────────────────────
  // Sesi di TrackingSessionManager adalah SATU-SATUNYA sumber titik & status
  // tracking project ini (diumpankan TrackingEngine, tak bergantung layar).
  TrackingSession? get _session =>
      TrackingSessionManager.instance.sessionFor(widget.project.id);

  /// Titik yang digambar/divalidasi/disimpan: milik sesi bila ada.
  List<GeoPoint> get _collectedPoints => _session?.points ?? _manualPoints;

  /// Sedang tracking = sesi ada & belum di-Stop (draft pendingSave = selesai).
  bool get _isTracking {
    final s = _session;
    return s != null && !s.pendingSave;
  }

  bool get _isPaused => _session?.paused ?? false;

  // ─── Marker animation ──────────────────────────────────────────────────────
  // Marker dianimasikan dari _markerBeginLatLng → _markerTargetLatLng
  // menggunakan AnimationController, sehingga pergerakan terlihat smooth.
  late AnimationController _markerAnimController;
  LatLng? _markerBeginLatLng;   // posisi awal animasi (posisi sebelumnya)
  LatLng? _markerTargetLatLng;  // posisi target animasi (posisi GPS terbaru)
  // ──────────────────────────────────────────────────────────────────────────

  // 🔧 FIX: Single unified stream for both tracking and blue marker
  StreamSubscription<GeoPoint>? _unifiedLocationSubscription;
  bool _isSaving = false;
  late final PdfOverlayController _pdfOverlay;
  Map<String, dynamic> _formData = {};
  CollectionMode _collectionMode = CollectionMode.tracking;
  Basemap? _selectedBasemap;
  bool _isLoadingLocation = true;
  bool _hasInitialZoom = false;
  StreamSubscription<CompassEvent>? _compassSubscription;
  bool _isBottomSheetExpanded = true;
  // ✅ Prominent Disclosure: tidak perlu track manual —
  // cukup cek status permission langsung (Opsi C)

  // Existing data from project
  List<GeoData> _existingData = [];
  String? _currentUsername;

  // P0+P1: Cached layers — computed once after data load, not on every build
  List<Marker> _cachedMarkers = [];
  List<Polyline> _cachedPolylines = [];
  List<Polygon> _cachedPolygons = [];

  // P2: Viewport-culled subset of cached layers
  List<Marker> _visibleMarkers = [];
  List<Polyline> _visiblePolylines = [];
  List<Polygon> _visiblePolygons = [];

  // P2+P3: Zoom tracking & culling debounce
  double _currentZoom = 15.0;
  Timer? _cullingDebounce;

  // GeoJSON Layers
  final LayerService _layerService = LayerService();
  List<LayerModel> _layers = [];
  final Map<String, Map<String, dynamic>> _layerGeoJsonCache = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Inisialisasi AnimationController untuk smooth marker movement. Hanya
    // layer marker (AnimatedBuilder) yang ikut per frame, bukan seluruh layar.
    _markerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Overlay PDF disiapkan sekali per ganti basemap (bukan di build).
    _pdfOverlay = PdfOverlayController(onProblem: _showBasemapProblem)
      ..addListener(_onPdfOverlayChanged);

    _setTransparentStatusBar();

    // Settings harus selesai dulu sebelum _loadExistingData()
    // agar _buildMarkerCache() langsung pakai warna/ukuran yang benar.
    // _loadExistingData() dipanggil di dalam _initializeSettingsThenLoadData().
    _initializeSettingsThenLoadData();

    _initializeServiceAndLocation();
    _loadBasemap();
    _initCompass();
    _loadActiveLayers();
    _loadUsername();

    // Rebuild marker cache setiap kali user mengubah settings
    _settingsService.addListener(_onSettingsChanged);

    // Layar mengikuti sesi project ini (titik & status) secara live.
    TrackingSessionManager.instance.addListener(_onSessionsChanged);
    _onSessionsChanged();

    // Emlid tersambung ulang otomatis → pasang ulang stream marker.
    _emlidWasConnected = _locationService.isEmlidConnected;
    _locationService.emlidStatus.addListener(_onEmlidStatusChanged);
  }

  void _onEmlidStatusChanged() {
    if (!mounted) return;
    final connected = _locationService.emlidStatus.value.connected;
    if (connected &&
        !_emlidWasConnected &&
        _locationService.currentProvider == LocationProvider.emlid) {
      logInfo('Emlid back online — restarting marker stream', tag: 'COLLECT');
      _startUnifiedLocationStream();
    }
    _emlidWasConnected = connected;
    setState(() {}); // ikon provider & banner
  }

  // Jejak terakhir yang dirender — manajer memberi notifikasi untuk SEMUA
  // project, jadi rebuild hanya bila sesi project ini benar-benar berubah.
  int _seenPointCount = -1;
  int _seenEditVersion = -1;
  SessionState? _seenState;

  void _onSessionsChanged() {
    if (!mounted) return;
    final s = _session;
    final count = s?.points.length ?? -1;
    final version = s?.editVersion ?? -1;
    if (count == _seenPointCount &&
        version == _seenEditVersion &&
        s?.state == _seenState) {
      return;
    }
    _seenPointCount = count;
    _seenEditVersion = version;
    _seenState = s?.state;
    setState(() {});
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

  /// Posisi marker yang diinterpolasi secara smooth antara posisi lama dan baru.
  /// Menggunakan easeOut curve agar terasa natural (cepat di awal, melambat di akhir).
  LatLng? get _animatedMarkerLatLng {
    final target = _markerTargetLatLng;
    if (target == null) return null;
    final begin = _markerBeginLatLng ?? target;
    final t = Curves.easeOut.transform(_markerAnimController.value);
    return LatLng(
      ui.lerpDouble(begin.latitude, target.latitude, t)!,
      ui.lerpDouble(begin.longitude, target.longitude, t)!,
    );
  }

  // ✅ NEW METHOD: Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    logDebug('📱 App lifecycle changed to: $state', tag: 'COLLECT');

    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground
        logDebug('✅ App resumed - location stream continues', tag: 'COLLECT');
        // P2: Skip stream restart if camera/gallery is open —
        // PhotoFieldWidget will handle retrieveLostData internally.
        // Restarting the stream here triggers a setState that can race
        // with the photo-save async chain.
        if (PhotoFieldWidget.isCameraActive) {
          logDebug('📷 Camera is active — skipping stream restart', tag: 'COLLECT');
          break;
        }
        // ✅ FIX: DON'T restart stream if already tracking
        // Background stream sudah jalan, biarkan terus
        // Tracking aktif: titik tetap masuk ke sesi lewat TrackingEngine selagi
        // app di background; layar cukup menampilkan sesi (listener manajer).
        if (!_isTracking) {
          // Only restart if not tracking (untuk blue dot)
          _startUnifiedLocationStream();
        }
        break;

      case AppLifecycleState.paused:
        // App went to background
        logDebug('⏸️ App paused - keeping background tracking alive', tag: 'COLLECT');
        // Jangan batalkan apa pun: TrackingEngine (app-level) menjaga service
        // + heartbeat selama ada sesi merekam.
        break;

      case AppLifecycleState.inactive:
        // App is inactive (e.g., during phone call)
        logDebug('😴 App inactive', tag: 'COLLECT');
        break;

      case AppLifecycleState.detached:
        // App is detached (about to be killed)
        logDebug('💀 App detached - cleaning up', tag: 'COLLECT');
        _cleanupBeforeTermination();
        break;

      case AppLifecycleState.hidden:
        // App is hidden (iOS specific)
        logDebug('🙈 App hidden', tag: 'COLLECT');
        break;
    }
  }


  void _cleanupBeforeTermination() {
    logDebug('🧹 Performing cleanup before app termination...', tag: 'COLLECT');

    // Cancel all streams that exist in data_collection_screen
    _unifiedLocationSubscription?.cancel();
    _compassSubscription?.cancel();

    // Service background dihentikan terpusat di main.dart (detached): flush
    // sesi ke SQLite lalu stop — berlaku walau layar ini tidak terbuka.
    logDebug('✅ Cleanup completed', tag: 'COLLECT');
  }

  // ✅ NEW METHOD: Override didPopRoute to stop tracking when user exits
  @override
  Future<bool> didPopRoute() async {
    logDebug('🚪 User is exiting DataCollectionScreen...', tag: 'COLLECT');
    
    // Multi-project: meninggalkan layar TIDAK menghentikan tracking. Sesi terus
    // berjalan di background (titik tetap terkumpul); user mengelola stop/simpan
    // dari daftar project lewat banner/panel "Tracking Aktif".
    if (_isTracking) {
      logDebug('▶️ Keluar layar — tracking lanjut di background (multi-project)', tag: 'COLLECT');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Tracking tetap berjalan. Kelola dari banner "Tracking Aktif" di daftar project.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
    return false; // selalu izinkan keluar
  }

  static const _bgRationaleDeclinedKey = 'bg_location_rationale_declined';

  /// Perlu menampilkan penjelasan izin lokasi latar belakang? Hanya bila izin
  /// "Always" belum ada DAN user belum pernah memilih "Not now" (dulu dialog
  /// muncul setiap kali layar dibuka & setiap Start).
  Future<bool> _shouldShowBackgroundRationale() async {
    try {
      final status = await Permission.locationAlways.status;
      if (status.isGranted) return false;
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_bgRationaleDeclinedKey) ?? false);
    } catch (e) {
      // Jika permission_handler error (misalnya di iOS simulator), skip modal
      logWarn('Could not check background location status: $e', tag: 'COLLECT');
      return false;
    }
  }

  Future<void> _rememberRationaleChoice(bool accepted) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_bgRationaleDeclinedKey, !accepted);
    } catch (e) {
      logWarn('Could not store background rationale choice: $e',
          tag: 'COLLECT');
    }
  }

  Future<void> _initializeServiceAndLocation() async {
    setState(() => _isLoadingLocation = true);

    // 1. GOOGLE PLAY: Prominent Disclosure sebelum meminta izin background.
    //    "Not now" hanya melewatkan izin background — GPS di layar tetap jalan.
    var requestBackground = true;
    if (await _shouldShowBackgroundRationale()) {
      if (!mounted) return;
      requestBackground = await _showBackgroundLocationRationale();
      await _rememberRationaleChoice(requestBackground);
      if (!requestBackground) {
        logInfo('Background location disclosure declined — foreground only',
            tag: 'COLLECT');
      }
    } else {
      final status = await Permission.locationAlways.status;
      requestBackground = status.isGranted;
    }

    // 2. Initialize LocationServiceV2 dengan proper error handling
    try {
      final initialized = await _locationService.initialize(
          requestBackground: requestBackground);
      if (!initialized) {
        throw Exception('Location permission was not granted or GPS is off.');
      }
      logDebug('✅ LocationService initialized successfully', tag: 'COLLECT');
    } catch (e, st) {
      logError('Location service initialization failed',
          tag: 'COLLECT', error: e, stack: st);
      if (mounted) {
        await _showInitializationErrorDialog(e);
        if (mounted) setState(() => _isLoadingLocation = false);
      }
      return;
    }

    await _initializeLocation();
  }

  /// Dialog saat layanan lokasi gagal disiapkan (izin ditolak / GPS mati).
  Future<void> _showInitializationErrorDialog(Object error) async {
    final message = error.toString().replaceFirst('Exception: ', '');
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Location is not available')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 16),
              const Text(
                'Please check:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildChecklistItem('Location permission is allowed for Terestria'),
              _buildChecklistItem('Location (GPS) is turned on'),
              _buildChecklistItem(
                  'Battery optimization is turned off for Terestria'),
              const SizedBox(height: 12),
              const Text(
                'You can continue without GPS and add points on the map, '
                'but tracking will not work.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context); // Exit data collection screen
            },
            child: const Text('Exit'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await PermissionService.openAppSettings();
            },
            child: const Text('Open settings'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Retry initialization
              await _initializeServiceAndLocation();
            },
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ✅ GOOGLE PLAY REQUIRED: Prominent Disclosure sebelum minta ACCESS_BACKGROUND_LOCATION
  // Wajib per kebijakan Google Play: https://support.google.com/googleplay/android-developer/answer/9799150
  Future<bool> _showBackgroundLocationRationale() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.blue, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Background location access',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Penjelasan fitur
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why Terestria needs this:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'To record your survey track with GPS in real time, including while the screen is locked or you switch to another app.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Data yang dikumpulkan
              const Text(
                'What is collected:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              _buildChecklistItem('GPS coordinates (latitude & longitude)'),
              _buildChecklistItem('Only while a tracking session is active'),
              _buildChecklistItem('Stored on this device and only sent to your organization\'s server when you sync'),
              const SizedBox(height: 14),
              // Cara mencabut
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You can revoke it at any time:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Settings → Apps → Terestria → Permissions → Location → "Allow only while using the app"',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Allow'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _setTransparentStatusBar() {
    // Set status bar transparan
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
  }

  /// Load settings terlebih dahulu, baru load existing data.
  /// Ini mencegah race condition di mana _buildMarkerCache() dipanggil
  /// sebelum settings selesai dimuat dari SharedPreferences.
  Future<void> _initializeSettingsThenLoadData() async {
    await _settingsService.initialize();
    if (mounted) await _loadExistingData();
    if (mounted) await _restoreDraft();
  }

  /// Dipanggil setiap kali settings berubah (listener di SettingsService).
  /// Rebuild marker cache agar warna & ukuran existing data langsung update.
  void _onSettingsChanged() {
    if (!mounted) return;
    if (_existingData.isEmpty) return;
    _buildMarkerCache();
    // Trigger culling ulang agar visibleMarkers ikut diperbarui
    _updateVisibleLayers();
    setState(() {});
  }

  void _initCompass() {
    // Notifier: hanya marker lokasi yang ikut berputar, bukan seluruh layar.
    _compassSubscription = FlutterCompass.events?.listen(
      (CompassEvent event) {
        final heading = event.heading;
        if (!mounted || heading == null) return;
        _bearingNotifier.value = heading;
      },
      onError: (Object e) =>
          logWarn('Compass unavailable: $e', tag: 'COLLECT'),
    );
  }

  // ──────────────────────────────────────────────────────
  // GeoJSON Layer helpers
  // ──────────────────────────────────────────────────────

  Future<void> _loadActiveLayers() async {
    try {
      final layers = await _layerService.loadLayers();
      // Pre-load GeoJSON for active layers
      final cache = <String, Map<String, dynamic>>{};
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
          _geoJsonLayerWidgets = _buildGeoJsonLayers();
        });
      }
    } catch (e, st) {
      logError('Could not load overlay layers', tag: 'COLLECT', error: e, stack: st);
    }
  }

  Future<void> _toggleLayerActive(LayerModel layer, bool active) async {
    try {
      await _layerService.toggleLayer(layer.id, active);
      Map<String, dynamic>? geoJson;
      if (active) geoJson = await _layerService.readGeoJson(layer.filePath);
      if (!mounted) return;
      setState(() {
        if (active && geoJson != null) {
          _layerGeoJsonCache[layer.id] = geoJson;
        } else if (!active) {
          _layerGeoJsonCache.remove(layer.id);
        }
        _layers = _layers
            .map((l) => l.id == layer.id ? l.copyWith(isActive: active) : l)
            .toList();
        _geoJsonLayerWidgets = _buildGeoJsonLayers();
      });
    } catch (e, st) {
      if (mounted) {
        showErrorFeedback(context, 'Could not show the layer "${layer.name}"',
            error: e, stack: st, tag: 'COLLECT');
      }
    }
  }

  void _showLayersPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LayersPanelSheet(
        layers: _layers,
        onToggle: (layer, active) => _toggleLayerActive(layer, active),
      ),
    );
  }

  List<Widget> _buildGeoJsonLayers() {
    final result = <Widget>[];
    for (final layer in _layers) {
      if (!layer.isActive) continue;
      final geoJson = _layerGeoJsonCache[layer.id];
      if (geoJson == null) continue;

      final features = geoJson['features'] as List<dynamic>? ?? [];
      final polylines = <Polyline>[];
      final polygons  = <Polygon>[];
      final markers   = <Marker>[];
      final labelMarkers = <Marker>[];

      var badFeatures = 0;
      for (final f in features) {
        // Satu fitur rusak tak boleh menggagalkan build seluruh peta.
        try {
          final feature = f as Map<String, dynamic>;
          final geom = feature['geometry'] as Map<String, dynamic>?;
          final props = feature['properties'] as Map<String, dynamic>? ?? {};
          if (geom == null) continue;

          final type = geom['type'] as String? ?? '';
          final label = layer.labelField != null
              ? props[layer.labelField]?.toString()
              : null;

          switch (type) {
            case 'Point':
              final coords = geom['coordinates'] as List<dynamic>;
              final latlng = LatLng(
                (coords[1] as num).toDouble(),
                (coords[0] as num).toDouble(),
              );
              markers.add(_buildPointMarker(latlng, layer));
              if (label != null) labelMarkers.add(_buildLabelMarker(latlng, label));
              break;

            case 'MultiPoint':
              for (final c in geom['coordinates'] as List<dynamic>) {
                final coords = c as List<dynamic>;
                final latlng = LatLng(
                  (coords[1] as num).toDouble(),
                  (coords[0] as num).toDouble(),
                );
                markers.add(_buildPointMarker(latlng, layer));
                if (label != null) labelMarkers.add(_buildLabelMarker(latlng, label));
              }
              break;

            case 'LineString':
              final pts = _coordsToLatLng(geom['coordinates'] as List<dynamic>);
              if (pts.length >= 2) {
                polylines.add(Polyline(
                  points: pts,
                  color: layer.style.strokeColor
                      .withOpacity(layer.style.fillOpacity),
                  strokeWidth: layer.style.strokeWidth,
                ));
                if (label != null) {
                  final mid = pts[pts.length ~/ 2];
                  labelMarkers.add(_buildLabelMarker(mid, label));
                }
              }
              break;

            case 'MultiLineString':
              for (final line in geom['coordinates'] as List<dynamic>) {
                final pts = _coordsToLatLng(line as List<dynamic>);
                if (pts.length >= 2) {
                  polylines.add(Polyline(
                    points: pts,
                    color: layer.style.strokeColor
                        .withOpacity(layer.style.fillOpacity),
                    strokeWidth: layer.style.strokeWidth,
                  ));
                  if (label != null) {
                    labelMarkers.add(_buildLabelMarker(pts[pts.length ~/ 2], label));
                  }
                }
              }
              break;

            case 'Polygon':
              final rings = geom['coordinates'] as List<dynamic>;
              final outer = _coordsToLatLng(rings[0] as List<dynamic>);
              if (outer.length >= 3) {
                polygons.add(Polygon(
                  points: outer,
                  color: layer.style.fillColor
                      .withOpacity(layer.style.fillOpacity),
                  borderColor: layer.style.strokeColor,
                  borderStrokeWidth: layer.style.strokeWidth,
                  isFilled: true,
                ));
                if (label != null) {
                  double sumLat = 0, sumLng = 0;
                  for (final p in outer) { sumLat += p.latitude; sumLng += p.longitude; }
                  final centroid = LatLng(sumLat / outer.length, sumLng / outer.length);
                  labelMarkers.add(_buildLabelMarker(centroid, label));
                }
              }
              break;

            case 'MultiPolygon':
              for (final poly in geom['coordinates'] as List<dynamic>) {
                final rings = poly as List<dynamic>;
                final outer = _coordsToLatLng(rings[0] as List<dynamic>);
                if (outer.length >= 3) {
                  polygons.add(Polygon(
                    points: outer,
                    color: layer.style.fillColor
                        .withOpacity(layer.style.fillOpacity),
                    borderColor: layer.style.strokeColor,
                    borderStrokeWidth: layer.style.strokeWidth,
                    isFilled: true,
                  ));
                  if (label != null) {
                    double sumLat = 0, sumLng = 0;
                    for (final p in outer) { sumLat += p.latitude; sumLng += p.longitude; }
                    final centroid = LatLng(sumLat / outer.length, sumLng / outer.length);
                    labelMarkers.add(_buildLabelMarker(centroid, label));
                  }
                }
              }
              break;
          }
        } catch (_) {
          badFeatures++;
        }
      }
      if (badFeatures > 0) {
        logWarn('Layer "${layer.name}": skipped $badFeatures invalid feature(s)',
            tag: 'COLLECT');
      }

      if (polylines.isNotEmpty) result.add(PolylineLayer(polylines: polylines));
      if (polygons.isNotEmpty)  result.add(PolygonLayer(polygons: polygons));
      if (markers.isNotEmpty)   result.add(MarkerLayer(markers: markers));
      if (labelMarkers.isNotEmpty) result.add(MarkerLayer(markers: labelMarkers));
    }
    return result;
  }

  Marker _buildPointMarker(LatLng latlng, LayerModel layer) {
    final size = layer.style.pointSize * 2;
    return Marker(
      point: latlng,
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          color: layer.style.fillColor.withOpacity(layer.style.fillOpacity),
          shape: BoxShape.circle,
          border: Border.all(
            color: layer.style.strokeColor,
            width: layer.style.strokeWidth.clamp(0.5, 3.0),
          ),
        ),
      ),
    );
  }

  Marker _buildLabelMarker(LatLng latlng, String label) {
    // Lebar tetap untuk label, tinggi = label (20) + jarak ke titik (12)
    const double markerW = 32;
    const double labelH  = 20;
    const double gapH    = 12; // jarak antara bawah label dan titik koordinat
    const double markerH = labelH + gapH;

    return Marker(
      point: latlng,
      width: markerW,
      height: markerH,
      // anchor di BAWAH-TENGAH widget sehingga titik (0,0) koordinat
      // tepat di pojok bawah-tengah → label mengapung di atasnya
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Label pill ──
          Container(
            height: labelH,
            constraints: const BoxConstraints(maxWidth: markerW),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
          // ── Jarak kosong ke titik ──
          const SizedBox(height: gapH),
        ],
      ),
    );
  }

  List<LatLng> _coordsToLatLng(List<dynamic> coords) {
    return coords.map((c) {
      final pair = c as List<dynamic>;
      return LatLng(
        (pair[1] as num).toDouble(),
        (pair[0] as num).toDouble(),
      );
    }).toList();
  }

  Future<void> _loadExistingData() async {
    try {
      final data = await _storageService.loadGeoData(widget.project.id);
      if (!mounted) return;
      setState(() => _existingData = data);
      _buildMarkerCache(); // P0+P1: build cache setelah data loaded
    } catch (e, st) {
      if (!mounted) return;
      showErrorFeedback(context, 'Could not load the saved records',
          error: e, stack: st, tag: 'COLLECT');
    }
  }

  // P0+P1: Bangun cache marker/polyline/polygon sekali dari _existingData.
  // Semua warna & ukuran diambil dari _settingsService.settings agar konsisten
  // dengan pengaturan yang dipilih user di halaman Settings.
  void _buildMarkerCache() {
    final s = _settingsService.settings; // shorthand agar kode lebih ringkas
    final markers = <Marker>[];
    final polylines = <Polyline>[];
    final polygons = <Polygon>[];

    // Ukuran marker existing data — sedikit lebih kecil dari active collection
    // agar bisa dibedakan secara visual, tapi tetap proporsional dengan pointSize.
    final markerDiameter = (s.pointSize * 2).clamp(20.0, 48.0);
    // Ukuran icon info (untuk label tengah line/polygon)
    final infoIconSize = (markerDiameter * 0.7).clamp(14.0, 26.0);

    for (final data in _existingData) {
      switch (widget.project.geometryType) {
        case GeometryType.point:
          if (data.points.isNotEmpty) {
            markers.add(Marker(
              point: LatLng(data.points.first.latitude, data.points.first.longitude),
              width: markerDiameter + 4,
              height: markerDiameter + 4,
              child: GestureDetector(
                onTap: () => _onExistingDataTap(data),
                child: Container(
                  width: markerDiameter,
                  height: markerDiameter,
                  decoration: BoxDecoration(
                    color: s.pointColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(Icons.location_on, color: Colors.white,
                      size: infoIconSize),
                ),
              ),
            ));
          }
          break;

        case GeometryType.line:
          if (data.points.isNotEmpty) {
            polylines.add(Polyline(
              points: data.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
              color: s.lineColor.withOpacity(0.8),
              strokeWidth: s.lineWidth,
            ));
            final centerIndex = data.points.length ~/ 2;
            markers.add(Marker(
              point: LatLng(
                data.points[centerIndex].latitude,
                data.points[centerIndex].longitude,
              ),
              width: markerDiameter + 4,
              height: markerDiameter + 4,
              child: GestureDetector(
                onTap: () => _onExistingDataTap(data),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: s.lineColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(Icons.info, color: s.lineColor,
                      size: infoIconSize),
                ),
              ),
            ));
          }
          break;

        case GeometryType.polygon:
          if (data.points.length >= 3) {
            polygons.add(Polygon(
              points: data.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
              color: s.polygonColor.withOpacity(s.polygonOpacity),
              borderColor: s.polygonColor.withOpacity(0.85),
              borderStrokeWidth: s.lineWidth,
              isFilled: true,
            ));
            // Hitung centroid sekali saja di sini, bukan di setiap build()
            double sumLat = 0, sumLng = 0;
            for (final p in data.points) {
              sumLat += p.latitude;
              sumLng += p.longitude;
            }
            markers.add(Marker(
              point: LatLng(sumLat / data.points.length, sumLng / data.points.length),
              width: markerDiameter + 4,
              height: markerDiameter + 4,
              child: GestureDetector(
                onTap: () => _onExistingDataTap(data),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: s.polygonColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(Icons.info, color: s.polygonColor,
                      size: infoIconSize),
                ),
              ),
            ));
          }
          break;
      }
    }

    _cachedMarkers = markers;
    _cachedPolylines = polylines;
    _cachedPolygons = polygons;

    // Inisialisasi visible = semua cached, lalu cull setelah map siap
    _visibleMarkers = markers;
    _visiblePolylines = polylines;
    _visiblePolygons = polygons;

    // Delay sedikit agar MapController sudah siap
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _updateVisibleLayers();
    });
  }

  // P2: Filter layers berdasarkan viewport map + buffer 30%
  void _updateVisibleLayers() {
    if (!mounted) return;
    if (_cachedMarkers.isEmpty && _cachedPolylines.isEmpty && _cachedPolygons.isEmpty) return;
    try {
      final bounds = _mapController.camera.visibleBounds;
      final latBuffer = (bounds.north - bounds.south) * 0.3;
      final lngBuffer = (bounds.east - bounds.west) * 0.3;
      final expanded = LatLngBounds(
        LatLng(bounds.south - latBuffer, bounds.west - lngBuffer),
        LatLng(bounds.north + latBuffer, bounds.east + lngBuffer),
      );

      setState(() {
        _visibleMarkers = _cachedMarkers
            .where((m) => expanded.contains(m.point))
            .toList();
        _visiblePolylines = _cachedPolylines
            .where((p) => p.points.any((pt) => expanded.contains(pt)))
            .toList();
        _visiblePolygons = _cachedPolygons
            .where((p) => p.points.any((pt) => expanded.contains(pt)))
            .toList();
      });
    } catch (_) {
      // Camera belum siap — pertahankan visible saat ini
    }
  }

  // P3: Grid-based clustering untuk point geometry
  // Zoom rendah → cluster, zoom tinggi → individual markers
  List<Marker> _getClusteredMarkers() {
    if (_visibleMarkers.isEmpty) return [];
    // Tampilkan individual jika zoom cukup tinggi atau data sedikit
    if (_currentZoom >= 14 || _visibleMarkers.length <= 30) {
      return _visibleMarkers;
    }

    // Ukuran grid cell berdasarkan zoom
    final cellSize = _currentZoom < 8
        ? 1.0
        : _currentZoom < 10
            ? 0.5
            : _currentZoom < 12
                ? 0.1
                : 0.05;

    final Map<String, List<Marker>> grid = {};
    for (final marker in _visibleMarkers) {
      final latCell = (marker.point.latitude / cellSize).floor();
      final lngCell = (marker.point.longitude / cellSize).floor();
      grid.putIfAbsent('$latCell:$lngCell', () => []).add(marker);
    }

    return grid.values.map((grouped) {
      if (grouped.length == 1) return grouped.first;

      // Centroid cluster
      final lat = grouped.map((m) => m.point.latitude).reduce((a, b) => a + b) / grouped.length;
      final lng = grouped.map((m) => m.point.longitude).reduce((a, b) => a + b) / grouped.length;
      final clusterPoint = LatLng(lat, lng);
      final count = grouped.length;

      return Marker(
        point: clusterPoint,
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () => _mapController.move(clusterPoint, _currentZoom + 2),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                count > 999 ? '999+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Future<void> _loadUsername() async {
    final authService = AuthService();
    final user = await authService.getUser();
    if (mounted) {
      setState(() {
        _currentUsername = user?.username;
      });
    }
  }

  bool _canEditGeoData(GeoData data) {
    if (_currentUsername == null) return false;
    if (data.collectedBy == null) return false;
    return data.collectedBy!.trim().toLowerCase() ==
        _currentUsername!.trim().toLowerCase();
  }

  Future<void> _editGeoData(GeoData data, BuildContext dialogContext) async {
    Navigator.pop(dialogContext); // tutup detail dialog dulu
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditGeoDataScreen(
          geoData: data,
          project: widget.project,
        ),
      ),
    );
    if (result == true) {
      await _loadExistingData();
    }
  }

  Future<void> _deleteGeoData(GeoData data, BuildContext dialogContext) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text(data.isSynced
            ? 'This record is already on the server. Deleting it here only '
                'removes it from this device — it stays on the server and can '
                'come back after a full download. Ask an administrator to '
                'delete it on the server.'
            : 'This record has not been uploaded yet. Deleting it removes it '
                'permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _storageService.deleteGeoData(data.id);
        logInfo('Deleted record ${data.id} (synced: ${data.isSynced})',
            tag: 'COLLECT');
        if (mounted) {
          Navigator.pop(dialogContext); // tutup detail dialog
          await _loadExistingData();
          if (mounted) showInfoFeedback(context, 'Record deleted');
        }
      } catch (e, st) {
        if (mounted) {
          showErrorFeedback(context, 'Could not delete the record',
              error: e, stack: st, tag: 'COLLECT');
        }
      }
    }
  }

  @override
  void dispose() {
    logDebug('🗑️ DataCollectionScreen dispose called', tag: 'COLLECT');

    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _pdfOverlay
      ..removeListener(_onPdfOverlayChanged)
      ..dispose();
    TrackingSessionManager.instance.removeListener(_onSessionsChanged);

    // Cancel compass stream (UI only)
    _compassSubscription?.cancel();

    // Cancel viewport culling debounce
    _cullingDebounce?.cancel();

    // Tracking TIDAK dihentikan di sini: service + heartbeat dimiliki
    // TrackingEngine (app-level) dan tetap hidup selama ada sesi merekam.

    // Cancel location stream
    _unifiedLocationSubscription?.cancel();
    logDebug('🗑️ Location stream cancelled', tag: 'COLLECT');

    // Dispose marker animation controller
    _markerAnimController.dispose();
    logDebug('🗑️ Marker animation controller disposed', tag: 'COLLECT');

    // Hapus settings listener
    _settingsService.removeListener(_onSettingsChanged);
    _locationService.emlidStatus.removeListener(_onEmlidStatusChanged);

    // Draft yang tertunda disimpan sekarang (keluar layar sebelum debounce).
    if (_draftDebounce?.isActive ?? false) {
      _draftDebounce!.cancel();
      _persistDraftNow();
    }
    _locationNotifier.dispose();
    _bearingNotifier.dispose();
    _centerNotifier.dispose();

    super.dispose();
  }

  Future<void> _loadBasemap() async {
    final basemap = await _basemapService.getSelectedBasemap();

    if (mounted) {
      setState(() => _selectedBasemap = basemap);
      _pdfOverlay.show(basemap);

      // Jika PDF basemap dengan georeferencing, zoom ke bounds PDF
      if (basemap.type == BasemapType.pdf && basemap.hasPdfGeoreferencing) {
        logDebug('PDF Basemap loaded, will zoom to bounds...', tag: 'COLLECT');
        logDebug('Bounds: Lat[${basemap.pdfMinLat}, ${basemap.pdfMaxLat}] Lon[${basemap.pdfMinLon}, ${basemap.pdfMaxLon}]', tag: 'COLLECT');

        // PENTING: Delay lebih lama dan pastikan map controller ready
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            try {
              // FIX: LatLngBounds constructor menerima southwest dan northeast corners
              // southwest = LatLng(minLat, minLon)
              // northeast = LatLng(maxLat, maxLon)
              final bounds = LatLngBounds(
                LatLng(
                    basemap.pdfMinLat!, basemap.pdfMinLon!), // southwest corner
                LatLng(
                    basemap.pdfMaxLat!, basemap.pdfMaxLon!), // northeast corner
              );

              logDebug('🔍 Fitting map to PDF bounds...', tag: 'COLLECT');
              logDebug('   Southwest: ${bounds.southWest}', tag: 'COLLECT');
              logDebug('   Northeast: ${bounds.northEast}', tag: 'COLLECT');

              // Fit bounds dengan padding
              _mapController.fitCamera(
                CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(50),
                ),
              );

              logDebug('✅ Map zoomed to PDF bounds', tag: 'COLLECT');
            } catch (e) {
              logError('❌ Error fitting bounds: $e', tag: 'COLLECT');
            }
          }
        });
      }
    }
  }

  Future<void> _initializeLocation() async {
    setState(() => _isLoadingLocation = true);

    // Load provider settings first
    await _locationService.loadLocationSettings();

    // 🔧 FIX: Start unified persistent stream immediately
    _startUnifiedLocationStream();

    // Try to get initial location for map centering
    GeoPoint? location;

    if (_locationService.currentProvider == LocationProvider.emlid) {
      // For Emlid, wait a bit for first data
      if (_locationService.isEmlidConnected) {
        try {
          location = await _locationService
              .trackEmlidLocation()
              .timeout(const Duration(seconds: 3))
              .first;
        } catch (e) {
          logDebug('Waiting for Emlid data: $e', tag: 'COLLECT');
          if (mounted) {
            showInfoFeedback(context, 'Waiting for RTK data…');
          }
        }
      } else if (mounted) {
        showInfoFeedback(
            context,
            _locationService.emlidStatus.value.reconnecting
                ? 'RTK receiver disconnected — reconnecting…'
                : 'RTK receiver is not connected. Open Location Provider to connect.',
            warning: true);
      }
    } else {
      // Use phone GPS
      location = await _locationService.getCurrentLocation();

      if (location == null && mounted) {
        showInfoFeedback(
            context,
            'No GPS position yet. Make sure location is on and move to open '
            'sky.',
            warning: true,
            duration: const Duration(seconds: 5));
      }
    }

    if (mounted) {
      setState(() => _isLoadingLocation = false);
    }

    // ✅ FIX: Capture location untuk avoid null safety issue
    final initialLocation = location;

    // Tampilkan marker SEGERA dari fix awal (getCurrentLocation/last-known) —
    // penting saat kembali ke layar sementara tracking jalan: stream background
    // hanya mengirim fix BERIKUTNYA, jadi tanpa priming ini marker akan kosong.
    if (initialLocation != null && mounted) {
      final ll = LatLng(initialLocation.latitude, initialLocation.longitude);
      _markerBeginLatLng = _markerTargetLatLng ?? ll;
      _markerTargetLatLng = ll;
      _currentLocation = initialLocation;
    }

    if (initialLocation != null && !_hasInitialZoom) {
      // Wait untuk map controller ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try {
            _mapController.move(
              LatLng(initialLocation.latitude, initialLocation.longitude), 
              15
            );
            _hasInitialZoom = true;
          } catch (e) {
            logWarn('⚠️ Could not move map on init: $e', tag: 'COLLECT');
          }
        }
      });
    }
  }

  // ✅ FIXED: Unified persistent location stream
  void _startUnifiedLocationStream() {
    logDebug('═══════════════════════════════════════', tag: 'COLLECT');
    logDebug('🔄 Restarting unified location stream...', tag: 'COLLECT');
    
    _unifiedLocationSubscription?.cancel();
    logDebug('✅ Previous subscription cancelled', tag: 'COLLECT');

    Stream<GeoPoint> locationStream;

    if (_locationService.currentProvider == LocationProvider.emlid) {
      if (_locationService.isEmlidConnected) {
        locationStream = _locationService.trackEmlidLocation();
        logDebug('📡 ✅ Using Emlid location stream', tag: 'COLLECT');
      } else {
        logWarn('⚠️ Emlid not connected, stream will be empty', tag: 'COLLECT');
        logDebug('═══════════════════════════════════════', tag: 'COLLECT');
        return;
      }
    } else {
      // Pakai stream background selama ADA sesi merekam (project mana pun) —
      // saat itu TrackingEngine menjaga service hidup. Tanpa sesi merekam,
      // service dimatikan → pakai stream foreground agar marker tetap jalan.
      if (TrackingSessionManager.instance.recordingCount > 0) {
        locationStream = _locationService.backgroundLocationStream;
        logDebug('📱 ✅ Using BACKGROUND location stream (tracking active)', tag: 'COLLECT');
      } else {
        locationStream = _locationService.trackLocation();
        logDebug('📱 ✅ Using FOREGROUND location stream (not tracking)', tag: 'COLLECT');
      }
    }

    _unifiedLocationSubscription = locationStream.listen(
      (location) {
        if (!mounted) return;
        final newLatLng = LatLng(location.latitude, location.longitude);
        // Tanpa setState: hanya layer marker (AnimatedBuilder) & panel status
        // (ValueListenableBuilder) yang dibangun ulang — bukan seluruh layar.
        // Stream ini HANYA untuk marker. Titik jalur masuk ke sesi lewat
        // TrackingEngine (feed per sumber) dan tampil via _onSessionsChanged.
        _markerBeginLatLng = _markerTargetLatLng ?? newLatLng;
        _markerTargetLatLng = newLatLng;
        _currentLocation = location;
        _markerAnimController.forward(from: 0);
      },
      onError: (Object error, StackTrace st) {
        logError('Location stream error', tag: 'COLLECT', error: error, stack: st);
        if (mounted) {
          showInfoFeedback(context,
              'GPS signal problem. Move to open sky; tracking continues when '
              'the signal returns.',
              warning: true);
        }
      },
    );
    
    logDebug('✅ Stream listener setup complete', tag: 'COLLECT');
    logDebug('═══════════════════════════════════════', tag: 'COLLECT');
  }

  void _toggleTracking() {
    if (_isTracking) {
      _finishTracking();
    } else {
      _startTracking();
    }
  }

  void _togglePause() {
    if (_isPaused) {
      _resumeTracking();
    } else {
      _pauseTracking();
    }
  }

  void _startTracking() async {
    // 1. Check Emlid connection first
    if (_locationService.currentProvider == LocationProvider.emlid) {
      if (!_locationService.isEmlidConnected) {
        if (mounted) {
          _showEmlidConnectionErrorDialog();
        }
        return;
      }
    }

    // 1b. Penyimpanan hampir penuh → titik bisa gagal tersimpan.
    if (!await confirmStorageFor(context, action: 'Tracking')) return;
    if (!mounted) return;

    // 1c. Start pertama hari ini: tawarkan checklist bila ada setelan yang
    //     bisa menghentikan tracking (izin, GPS mati, optimasi baterai).
    if (!await maybeShowDailyReadinessCheck(context)) return;
    if (!mounted) return;

    // 2. GOOGLE PLAY: Prominent Disclosure sebelum meminta izin background.
    //    Android: foreground service tetap merekam dengan izin "saat
    //    digunakan", jadi "Not now" TIDAK memblokir tracking (dulu memblokir).
    if (await _shouldShowBackgroundRationale()) {
      if (!mounted) return;
      final allow = await _showBackgroundLocationRationale();
      await _rememberRationaleChoice(allow);
      if (allow) {
        await PermissionService.requestBackgroundLocation();
      } else if (Platform.isIOS && mounted) {
        showInfoFeedback(
            context,
            'Without "Always" location access, iOS may pause tracking while '
            'Terestria is in the background.',
            warning: true,
            duration: const Duration(seconds: 5));
      }
      if (!mounted) return;
    }

    // 2b. Daftarkan sesi ke manajer multi-project (guard cap + no-dup), terikat
    //     ke sumber GPS aktif agar jalur RTK tak tercampur GPS HP.
    final source = _locationService.currentProvider == LocationProvider.emlid
        ? TrackSource.emlid
        : TrackSource.phone;
    final startRes =
        TrackingSessionManager.instance.start(widget.project, source: source);
    if (startRes.status == StartStatus.capReached) {
      if (mounted) {
        showInfoFeedback(
            context,
            'At most ${TrackingSessionManager.instance.maxConcurrent} projects '
            'can track at the same time. Stop one of them first.',
            warning: true);
      }
      return;
    }
    // Melanjutkan sesi lama yang direkam dari sumber GPS lain → beri tahu:
    // titik dari provider aktif sekarang tidak akan masuk ke sesi ini.
    final existing = startRes.session;
    if (startRes.status == StartStatus.alreadyActive &&
        existing != null &&
        existing.source != source &&
        mounted) {
      showInfoFeedback(
          context,
          existing.source == TrackSource.emlid
              ? 'This session was recorded with RTK GPS — connect the Emlid '
                  'receiver so new points are added.'
              : 'This session was recorded with phone GPS — switch the '
                  'provider to Phone so new points are added.',
          warning: true,
          duration: const Duration(seconds: 5));
    }
    final mgr = TrackingSessionManager.instance;
    // Sesi baru: titik manual yang sudah ada ikut masuk (perilaku lama —
    // tracking melanjutkan daftar titik yang sama).
    if (startRes.status == StartStatus.started && _manualPoints.isNotEmpty) {
      for (final p in _manualPoints) {
        mgr.appendManual(widget.project.id, p);
      }
      _manualPoints.clear();
    }
    // Lanjutkan sesi bila sebelumnya di-pause / draft (re-start setelah Stop).
    final prevState = existing?.state;
    mgr.resume(widget.project.id);

    // 3. Pastikan feed GPS hidup. Service + heartbeat dimiliki TrackingEngine
    //    (app-level) — tetap jalan walau layar ini ditutup.
    try {
      final success = await TrackingEngine.instance.ensureRunning();

      if (!success) {
        throw Exception('Background tracking service failed to start');
      }

      logDebug('✅ Background tracking service started successfully', tag: 'COLLECT');
    } catch (e, stack) {
      logError('❌ Error starting background tracking: $e', tag: 'COLLECT');
      crashlytics.log('Tracking start failed: $e');
      crashlytics.setContext('project_id', widget.project.id);
      crashlytics.setContext('geometry_type',
          widget.project.geometryType.toString().split('.').last);
      crashlytics.setContext('point_count', _collectedPoints.length);
      crashlytics.recordError(e, stack,
          reason: 'DataCollection: startBackgroundTracking failed');

      // Rollback: sesi baru dilepas (titik manual dikembalikan); sesi lama
      // dikembalikan ke status sebelumnya.
      if (startRes.status == StartStatus.started) {
        _manualPoints.addAll(mgr.stop(widget.project.id)?.points ?? const []);
      } else if (prevState == SessionState.pendingSave) {
        mgr.finish(widget.project.id);
      } else if (prevState == SessionState.paused) {
        mgr.pause(widget.project.id);
      }

      if (mounted) {
        await _showTrackingErrorDialog(e.toString());
      }
      return;
    }

    logDebug('✅ Tracking started successfully (provider: ${_locationService.currentProvider.name})', tag: 'COLLECT');

    // 4. Show success message
    HapticFeedback.mediumImpact();
    logInfo('Tracking started for "${widget.project.name}" '
        '(${_locationService.currentProvider.name})', tag: 'COLLECT');
    if (mounted) {
      final providerName =
          _locationService.currentProvider == LocationProvider.emlid
              ? 'RTK GPS'
              : 'phone GPS';
      showInfoFeedback(
          context,
          'Tracking started with $providerName. It continues with the screen '
          'off — but do not swipe Terestria away from recent apps, that stops '
          'tracking.',
          success: true,
          duration: const Duration(seconds: 5));
    }

    // 5. ✅ CRITICAL FIX: Restart stream untuk switch ke background stream
    await Future.delayed(const Duration(milliseconds: 500));
    _startUnifiedLocationStream();
    logDebug('✅ Stream restarted to use background location stream', tag: 'COLLECT');
  }

// ✅ NEW METHOD: Show Emlid connection error dialog
  Future<void> _showEmlidConnectionErrorDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('RTK GPS Not Connected'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cannot start tracking because RTK GPS is not connected.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'To use RTK GPS:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildChecklistItem('Connect to Emlid WiFi hotspot'),
            _buildChecklistItem('Open Location Provider settings'),
            _buildChecklistItem('Connect to RTK GPS device'),
            _buildChecklistItem('Wait for data streaming'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Navigate to Location Provider screen
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LocationProviderScreen(),
                ),
              );
              // Retry if settings changed
              if (result == true && mounted) {
                _startUnifiedLocationStream();
              }
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Dialog saat service tracking gagal dinyalakan.
  Future<void> _showTrackingErrorDialog(String error) async {
    logWarn('Tracking could not start: $error', tag: 'COLLECT');
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Tracking could not start')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The GPS tracking service did not start. Please check:',
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              _buildChecklistItem('Location permission is allowed'),
              _buildChecklistItem('Location (GPS) is turned on'),
              _buildChecklistItem('Notifications are allowed (Android 13+)'),
              _buildChecklistItem(
                  'Battery optimization is off for Terestria'),
              const SizedBox(height: 12),
              const Text(
                'Your collected points are kept. Fix the setting, then tap '
                'Retry.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Checklist dengan tombol perbaikan per butir (izin, baterai…).
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const FieldReadinessScreen()));
            },
            child: const Text('Check & fix'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _startTracking();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _pauseTracking() async {
    // Status pause milik sesi (layar ikut via listener). Bila ini sesi merekam
    // terakhir, TrackingEngine mematikan service.
    TrackingSessionManager.instance.pause(widget.project.id);
    _startUnifiedLocationStream(); // pilih ulang stream (bg ↔ fg)
    HapticFeedback.lightImpact();
    logInfo('Tracking paused for "${widget.project.name}"', tag: 'COLLECT');
    if (mounted) {
      showInfoFeedback(context, 'Tracking paused — new points are not recorded.',
          duration: const Duration(seconds: 2));
    }
  }

  void _resumeTracking() async {
    TrackingSessionManager.instance.resume(widget.project.id);

    // Resume bisa menyalakan service kembali (mis. sesi hasil restore).
    final ok = await TrackingEngine.instance.ensureRunning();
    if (!mounted) return;
    if (!ok) {
      TrackingSessionManager.instance.pause(widget.project.id);
      logWarn('Resume failed: tracking service did not start', tag: 'COLLECT');
      showInfoFeedback(context,
          'Could not start background GPS. Check the location permission.',
          warning: true);
      return;
    }
    _startUnifiedLocationStream(); // pilih ulang stream (fg → bg)
    HapticFeedback.lightImpact();
    logInfo('Tracking resumed for "${widget.project.name}"', tag: 'COLLECT');
    showInfoFeedback(context, 'Tracking resumed',
        duration: const Duration(seconds: 2));
  }

  void _finishTracking() async {
    // Sesi jadi draft pendingSave: berhenti bertambah, tak menahan cap maupun
    // service (TrackingEngine mematikan service bila tak ada project lain yang
    // merekam). Simpan/Buang melepas sesi sepenuhnya.
    TrackingSessionManager.instance.finish(widget.project.id);
    HapticFeedback.mediumImpact();
    logInfo('Tracking stopped for "${widget.project.name}" '
        '(${_collectedPoints.length} points)', tag: 'COLLECT');
    if (mounted) {
      showInfoFeedback(context,
          'Tracking stopped. Tap ✓ to save, or Start to continue the track.',
          duration: const Duration(seconds: 3));
    }

    // 🔧 FIXED: Restart stream for foreground location only
    _startUnifiedLocationStream();
  }

  // ─── Draft (titik manual + isian form) ───────────────────────────────────

  /// Simpan draft sesaat setelah perubahan terakhir (debounce).
  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 800), _persistDraftNow);
  }

  void _persistDraftNow() {
    // Titik sesi tracking dicadangkan terpisah oleh koordinator persistensi;
    // draft cukup menyimpan titik manual + isian form.
    unawaited(_draftService.save(
      widget.project.id,
      points: _session == null ? List.of(_manualPoints) : const [],
      formData: _formData,
    ));
  }

  /// Pulihkan draft yang tertinggal (mis. app dibunuh saat kamera terbuka).
  Future<void> _restoreDraft() async {
    final draft = await _draftService.load(widget.project.id);
    if (draft == null || !mounted) return;
    final restorePoints = _session == null && draft.points.isNotEmpty;
    setState(() {
      if (restorePoints) {
        _manualPoints
          ..clear()
          ..addAll(draft.points);
      }
      _formData = Map<String, dynamic>.of(draft.formData);
    });
    logInfo(
        'Restored collection draft: '
        '${restorePoints ? draft.points.length : 0} point(s), '
        '${draft.formData.length} field value(s)',
        tag: 'DRAFT');
    final parts = [
      if (restorePoints)
        '${draft.points.length} point${draft.points.length > 1 ? 's' : ''}',
      if (draft.formData.isNotEmpty) 'form values',
    ];
    if (parts.isEmpty) return;
    showInfoFeedback(
      context,
      'Restored your unsaved work (${parts.join(' and ')}).',
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'DISCARD', onPressed: _discardDraft),
    );
  }

  void _discardDraft() {
    if (!mounted) return;
    setState(() {
      if (_session == null) _manualPoints.clear();
      _formData = {};
    });
    _draftDebounce?.cancel();
    unawaited(_draftService.clear(widget.project.id));
    logInfo('Collection draft discarded by user', tag: 'DRAFT');
  }

  // ─── Mutasi titik: lewat sesi bila ada (ter-persist & tampil di panel),
  //     selain itu daftar manual lokal (+ draft). ───────────────────────────
  void _appendPoint(GeoPoint p) {
    if (_session != null) {
      TrackingSessionManager.instance.appendManual(widget.project.id, p);
    } else {
      setState(() => _manualPoints.add(p));
      _scheduleDraftSave();
    }
  }

  void _removeLastPoint() {
    if (_session != null) {
      TrackingSessionManager.instance.removeLast(widget.project.id);
    } else if (_manualPoints.isNotEmpty) {
      _manualPoints.removeLast();
      _scheduleDraftSave();
    }
  }

  /// Hapus semua titik; mengembalikan salinannya untuk "Undo".
  List<GeoPoint> _clearAllPoints() {
    final snapshot = List<GeoPoint>.of(_collectedPoints);
    if (_session != null) {
      TrackingSessionManager.instance.clearPoints(widget.project.id);
    } else {
      _manualPoints.clear();
      _scheduleDraftSave();
    }
    return snapshot;
  }

  void _restorePoints(List<GeoPoint> points) {
    if (!mounted) return;
    if (_session != null) {
      TrackingSessionManager.instance.replacePoints(widget.project.id, points);
    } else {
      setState(() {
        _manualPoints
          ..clear()
          ..addAll(points);
      });
      _scheduleDraftSave();
    }
    logInfo('Undo clear: ${points.length} point(s) restored', tag: 'COLLECT');
  }

  void _addCurrentPoint() async {
    // Untuk point geometry, hanya bisa add 1 point
    if (widget.project.geometryType == GeometryType.point &&
        _collectedPoints.isNotEmpty) {
      showInfoFeedback(context,
          'A point record has one point. Save it, or tap Undo to place it again.',
          warning: true);
      return;
    }

    // Titik di crosshair (tengah peta) — tombol "My Location" memusatkan peta
    // ke posisi GPS bila titik harus di posisi sekarang.
    final center = _mapController.camera.center;
    _appendPoint(GeoPoint(
      latitude: center.latitude,
      longitude: center.longitude,
      timestamp: DateTime.now(),
    ));
    HapticFeedback.selectionClick();

    // Peringatkan (tanpa memblok) bila fix GPS saat ini di bawah syarat
    // kualitas yang dipilih — jangan diam-diam menyimpan titik bermutu rendah.
    final loc = _currentLocation;
    if (loc != null && !_locationService.pointMeetsCurrentRequirement(loc)) {
      showInfoFeedback(
          context,
          'Point added at the crosshair. GPS quality is below the '
          '"${_locationService.currentFixQuality.name}" requirement '
          '(±${loc.accuracy?.toStringAsFixed(1) ?? '?'} m).',
          warning: true);
      return;
    }

    showInfoFeedback(context,
        'Point ${_collectedPoints.length} added at the crosshair',
        duration: const Duration(seconds: 1));
  }

  bool _canSaveData() {
    // Validator berdasarkan tipe geometri
    if (widget.project.geometryType == GeometryType.point) {
      return _collectedPoints.length >= 1; // Point: minimal 1 titik
    } else if (widget.project.geometryType == GeometryType.line) {
      return _collectedPoints.length >= 2; // Line: minimal 2 titik
    } else if (widget.project.geometryType == GeometryType.polygon) {
      return _collectedPoints.length >= 3; // Polygon: minimal 3 titik
    }
    return false;
  }

  String _getConfirmTooltip() {
    // Tooltip yang informatif berdasarkan kondisi
    if (_collectedPoints.isEmpty) {
      return 'No points collected';
    }

    if (widget.project.geometryType == GeometryType.point) {
      return 'Save data';
    } else if (widget.project.geometryType == GeometryType.line) {
      if (_collectedPoints.length >= 2) {
        return 'Save data';
      }
      return 'Need ${2 - _collectedPoints.length} more point(s)';
    } else if (widget.project.geometryType == GeometryType.polygon) {
      if (_collectedPoints.length >= 3) {
        return 'Save data';
      }
      return 'Need ${3 - _collectedPoints.length} more point(s)';
    }
    return 'Save data';
  }

  void _undoLastPoint() {
    if (_collectedPoints.isNotEmpty) {
      setState(() {
        _removeLastPoint();
        // Hide form if below minimum points
        if (widget.project.geometryType == GeometryType.point &&
            _collectedPoints.isEmpty) {
        } else if (widget.project.geometryType == GeometryType.line &&
            _collectedPoints.length < 2) {
        } else if (widget.project.geometryType == GeometryType.polygon &&
            _collectedPoints.length < 3) {
        }
      });
      HapticFeedback.selectionClick();
    }
  }

  /// Hapus semua titik — dengan konfirmasi & "Undo" (dulu satu ketukan
  /// langsung menghapus track berjam-jam).
  Future<void> _clearPoints() async {
    final count = _collectedPoints.length;
    if (count == 0) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_outlined,
            color: Colors.red, size: 32),
        title: const Text('Clear all points?'),
        content: Text(
            'This removes all $count point${count > 1 ? 's' : ''} of the '
            'current ${_isTracking ? 'track' : 'record'}. You can undo right '
            'after.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    late List<GeoPoint> snapshot;
    setState(() {
      snapshot = _clearAllPoints();
    });
    HapticFeedback.mediumImpact();
    logInfo('Cleared $count point(s) in "${widget.project.name}" '
        '(undo available)', tag: 'COLLECT');
    showInfoFeedback(
      context,
      'Cleared $count point${count > 1 ? 's' : ''}',
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () => _restorePoints(snapshot),
      ),
    );
  }

  /// Simpan record. Form yang belum lengkap DIBLOKIR (dulu tetap tersimpan)
  /// dan layar digulir ke field bermasalah. [continueCollecting] = "Save &
  /// next": tetap di peta dengan form kosong (nilai ter-pin tetap).
  Future<bool> _saveData({bool continueCollecting = false}) async {
    if (_collectedPoints.isEmpty) {
      showInfoFeedback(context, 'Add at least one point first.', warning: true);
      return false;
    }

    _formKey.currentState?.save();
    final formValid = _formKey.currentState?.validate() ?? true;
    final issues = formFieldIssues(widget.project.formFields, _formData);
    if (issues.isNotEmpty || !formValid) {
      if (issues.isNotEmpty) _formController.scrollTo(issues.first.field.label);
      final first = issues.isNotEmpty ? issues.first : null;
      showInfoFeedback(
        context,
        first == null
            ? 'Some fields need attention.'
            : '"${first.field.label}" ${first.message}'
                '${issues.length > 1 ? ' (+${issues.length - 1} more)' : ''}.',
        warning: true,
        duration: const Duration(seconds: 4),
      );
      logInfo('Save blocked: ${issues.length} field issue(s)', tag: 'COLLECT');
      return false;
    }

    final geometry =
        validateGeometry(widget.project.geometryType, _collectedPoints.length);
    if (!geometry.ok) {
      showInfoFeedback(context, geometry.error ?? 'Not enough points.',
          warning: true);
      return false;
    }

    setState(() => _isSaving = true);

    try {
      // Ambil username dari AuthService
      final user = await AuthService().getUser();

      final geoData = GeoData(
        id: _uuid.v4(),
        projectId: widget.project.id,
        formData: Map<String, dynamic>.of(_formData),
        // Salinan: list sesi dilepas setelah simpan (manager.stop).
        points: List.of(_collectedPoints),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        collectedBy: user?.username,
      );

      await _storageService.saveGeoData(geoData);

      // Sesi project ini selesai → lepas dari manajer multi-project.
      TrackingSessionManager.instance.stop(widget.project.id);
      _manualPoints.clear();
      _draftDebounce?.cancel();
      await _draftService.clear(widget.project.id);
      HapticFeedback.mediumImpact();
      logInfo(
          'Saved record ${geoData.id} (${geoData.points.length} point(s)) '
          'in "${widget.project.name}"',
          tag: 'COLLECT');

      if (!mounted) return true;
      setState(() => _isSaving = false);

      if (continueCollecting) {
        // Tutup form, kosongkan isian (nilai pin dimuat ulang saat form
        // dibuka lagi), tetap di peta untuk record berikutnya.
        _formData = {};
        Navigator.pop(context);
        await _loadExistingData();
        if (mounted) {
          showInfoFeedback(context, 'Saved. Ready for the next record.',
              success: true);
        }
      } else {
        // Simpan context sebelum pop untuk SnackBar
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        Navigator.pop(context); // form
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted) {
          // Pop DataCollectionScreen dengan result=true untuk trigger reload
          Navigator.pop(context, true);
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: const Text('Record saved'),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
      return true;
    } catch (e, stack) {
      if (mounted) setState(() => _isSaving = false);
      crashlytics.log('saveData failed for project ${widget.project.id}');
      crashlytics.setContext('project_id', widget.project.id);
      crashlytics.setContext('geometry_type',
          widget.project.geometryType.toString().split('.').last);
      crashlytics.setContext('point_count', _collectedPoints.length);
      crashlytics.setContext(
          'form_fields', widget.project.formFields.length);
      crashlytics.recordError(e, stack,
          reason: 'DataCollection: saveGeoData failed');
      if (mounted) {
        // Titik & isian tetap ada (draft) — user bisa mencoba lagi.
        _persistDraftNow();
        showErrorFeedback(context, 'Could not save the record',
            error: e, stack: stack, tag: 'COLLECT', log: false);
      }
      return false;
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_collectionMode == CollectionMode.drawing && !_isTracking) {
      _appendPoint(GeoPoint(
        latitude: point.latitude,
        longitude: point.longitude,
        timestamp: DateTime.now(),
      ));
      HapticFeedback.selectionClick();
    }
  }

  void _onExistingDataTap(GeoData data) {
    _showDataDetail(data);
  }

  bool _isPhotoField(String fieldName) {
    final field = widget.project.formFields
        .where((f) => f.label == fieldName)
        .firstOrNull;
    if (field != null) {
      return field.type == FieldType.photo;
    }

    final lowerName = fieldName.toLowerCase();
    return lowerName.contains('photo') ||
        lowerName.contains('image') ||
        lowerName.contains('picture') ||
        lowerName.contains('foto') ||
        lowerName.contains('gambar');
  }

  bool _isOssField(String fieldName) {
    // Exclude fields yang berakhiran _oss_urls, _oss_keys, atau mengandung 'oss'
    final lowerName = fieldName.toLowerCase();
    return lowerName.endsWith('_oss_urls') ||
        lowerName.endsWith('_oss_keys') ||
        lowerName.endsWith('_oss_url') ||
        lowerName.endsWith('_oss_key') ||
        lowerName.contains('_oss_') ||
        lowerName.startsWith('oss_');
  }

  IconData _getGeometryIcon() {
    switch (widget.project.geometryType) {
      case GeometryType.point:
        return Icons.location_on;
      case GeometryType.line:
        return Icons.timeline;
      case GeometryType.polygon:
        return Icons.pentagon_outlined;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showFullImage(String imagePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Photo'),
            backgroundColor: Colors.black,
          ),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(File(imagePath)),
            ),
          ),
        ),
      ),
    );
  }

  void _showDataDetail(GeoData data) {
    final canEdit = _canEditGeoData(data);
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getGeometryIcon(),
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Survey Data Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(data.createdAt),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildDataDetailContent(data),
                ),
              ),

              // Footer: Edit & Delete (hanya jika punya akses)
              if (canEdit)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border(
                      top: BorderSide(color: Colors.grey[200]!),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Delete button
                      OutlinedButton.icon(
                        onPressed: () => _deleteGeoData(data, dialogContext),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete'),
                      ),
                      const Spacer(),
                      // Edit button
                      ElevatedButton.icon(
                        onPressed: () => _editGeoData(data, dialogContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataDetailContent(GeoData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photo fields
        ...data.formData.entries
            .where(
                (entry) => _isPhotoField(entry.key) && !_isOssField(entry.key))
            .map((entry) {
          // Handle PhotoMetadata format
          List<String> photoPaths = [];

          if (entry.value is List) {
            final list = entry.value as List;

            for (var item in list) {
              // Handle PhotoMetadata format
              if (item is Map) {
                final localPath = item['localPath'];
                if (localPath != null && localPath.toString().isNotEmpty) {
                  final pathStr = localPath.toString();
                  final file = File(pathStr);
                  if (file.existsSync()) {
                    photoPaths.add(pathStr);
                  }
                }
              }
              // Handle old string format (backward compatibility)
              else if (item is String && item.isNotEmpty) {
                final file = File(item);
                if (file.existsSync()) {
                  photoPaths.add(item);
                }
              }
            }
          } else if (entry.value is String &&
              entry.value.toString().isNotEmpty) {
            final path = entry.value.toString();
            final file = File(path);
            if (file.existsSync()) {
              photoPaths = [path];
            }
          }

          if (photoPaths.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.photo_camera,
                        size: 20,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          Text(
                            '${photoPaths.length} photo${photoPaths.length > 1 ? "s" : ""}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Display photos in a grid if multiple
                if (photoPaths.length > 1)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: photoPaths.length,
                    itemBuilder: (context, index) {
                      final photoPath = photoPaths[index];
                      final photoFile = File(photoPath);
                      final fileExists = photoFile.existsSync();

                      return GestureDetector(
                        onTap: () {
                          if (fileExists) {
                            _showFullImage(photoPath);
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: fileExists
                                ? Image.file(
                                    photoFile,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _buildImageErrorWidget();
                                    },
                                  )
                                : _buildImageNotFoundWidget(photoPath),
                          ),
                        ),
                      );
                    },
                  )
                else
                  // Single photo display
                  GestureDetector(
                    onTap: () {
                      final photoFile = File(photoPaths[0]);
                      if (photoFile.existsSync()) {
                        _showFullImage(photoPaths[0]);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: () {
                          final photoFile = File(photoPaths[0]);
                          final fileExists = photoFile.existsSync();

                          if (fileExists) {
                            return Image.file(
                              photoFile,
                              width: double.infinity,
                              height: 250,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildImageErrorWidget();
                              },
                            );
                          } else {
                            return _buildImageNotFoundWidget(photoPaths[0]);
                          }
                        }(),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            );
          }
          return const SizedBox.shrink();
        }),

        // Non-photo form fields
        if (data.formData.entries.any((entry) =>
            !_isPhotoField(entry.key) && !_isOssField(entry.key))) ...[
          const Row(
            children: [
              Icon(Icons.description_outlined,
                  size: 20, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text('Form Data',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          ...data.formData.entries
              .where((entry) =>
                  !_isPhotoField(entry.key) && !_isOssField(entry.key))
              .map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.key,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(entry.value.toString(),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],

        // Location info
        const Row(
          children: [
            Icon(Icons.my_location, size: 20, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Text('Location Points',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on,
                  color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                '${data.points.length} point${data.points.length > 1 ? "s" : ""} recorded',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showBasemapSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => BasemapSelectorSheet(
        currentBasemap: _selectedBasemap,
        onBasemapSelected: (basemap) {
          setState(() => _selectedBasemap = basemap);
          _basemapService.setSelectedBasemap(basemap.id);
          _pdfOverlay.show(basemap);
          fitCameraToPdfIfOffscreen(_mapController, basemap);
        },
      ),
    );
  }

  void _showOfflineDownloadDialog() {
    // Check if basemap is suitable for offline download
    if (_selectedBasemap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a basemap first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_selectedBasemap!.type == BasemapType.pdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF basemaps cannot be downloaded for offline use'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_selectedBasemap!.urlTemplate.isEmpty ||
        _selectedBasemap!.urlTemplate.startsWith('sqlite://') ||
        _selectedBasemap!.urlTemplate.startsWith('overlay://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This basemap does not support offline download'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Get current visible bounds from flutter_map
    final flutterMapBounds = _mapController.camera.visibleBounds;

    // Convert flutter_map LatLngBounds to our custom LatLngBounds
    final customBounds = custom_bounds.LatLngBounds(
      northWest: LatLng(
        flutterMapBounds.north,
        flutterMapBounds.west,
      ),
      southEast: LatLng(
        flutterMapBounds.south,
        flutterMapBounds.east,
      ),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => OfflineDownloadDialog(
        visibleBounds: customBounds,
        currentBasemap: _selectedBasemap!,
      ),
    );
  }

  /// Konfirmasi sebelum form atribut: HANYA muncul bila ada yang perlu
  /// diperhatikan — GPS saat ini di bawah syarat kualitas, atau geometri
  /// janggal (tepi poligon berpotongan, luas/panjang ≈0, titik ganda).
  /// Dulu dialog wajib muncul di setiap simpan. Return true = lanjut ke form.
  Future<bool> _confirmBeforeForm() async {
    final loc = _currentLocation;
    final meetsReq =
        loc == null || _locationService.pointMeetsCurrentRequirement(loc);
    final warnings =
        geometryWarnings(widget.project.geometryType, _collectedPoints);
    if (meetsReq && warnings.isEmpty) return true;

    final acc = loc?.accuracy;
    final reqName = _locationService.currentFixQuality.name;
    logInfo(
        'Pre-save check: gps ok=$meetsReq, geometry warnings=${warnings.length}',
        tag: 'COLLECT');
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Icons.warning_amber_rounded,
            color: Colors.orange.shade800, size: 36),
        title: const Text('Check before saving'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!meetsReq)
                _buildWarningLine(
                  'GPS accuracy is ${acc != null ? '±${acc.toStringAsFixed(1)} m' : 'unknown'}, '
                  'below the "$reqName" requirement. Points placed from GPS '
                  'may be inaccurate.',
                ),
              for (final w in warnings) _buildWarningLine(w),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Review points'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildWarningLine(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
          ],
        ),
      );

  void _showFormBottomSheet() {
    bool localIsSaving = false;

    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> save({required bool next}) async {
              setModalState(() => localIsSaving = true);
              final ok = await _saveData(continueCollecting: next);
              // Gagal / diblokir → form tetap terbuka untuk diperbaiki.
              if (!ok && context.mounted) {
                setModalState(() => localIsSaving = false);
              }
            }

            return Scaffold(
              appBar: AppBar(
                title: const Text('Survey data'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close (your entries are kept)',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: SafeArea(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(AppTheme.spacingMedium),
                          children: [
                            RequiredFieldsProgress(
                              fields: widget.project.formFields,
                              data: _formData,
                            ),
                            DynamicForm(
                              formFields: widget.project.formFields,
                              projectId: widget.project.id,
                              // Isian dipertahankan saat form ditutup & dibuka
                              // lagi (dulu kosong kembali).
                              initialData: _formData,
                              controller: _formController,
                              onSaved: (data) => _formData = data,
                              // Pass watermark info to PhotoFieldWidget
                              username: _currentUsername,
                              latitude: _currentLocation?.latitude,
                              longitude: _currentLocation?.longitude,
                              locationProvider: () => _locationNotifier.value,
                              onChanged: () {
                                _scheduleDraftSave();
                                if (context.mounted) setModalState(() {});
                              },
                            ),
                            const SizedBox(height: 100), // Extra space for button
                          ],
                        ),
                      ),
                      // Tombol simpan di bawah — selalu aktif; bila ada field
                      // bermasalah, form menggulir ke field itu.
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: localIsSaving
                                      ? null
                                      : () => save(next: true),
                                  icon: const Icon(Icons.add_location_alt,
                                      size: 20),
                                  label: const Text('Save & next'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: localIsSaving
                                      ? null
                                      : () => save(next: false),
                                  icon: localIsSaving
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.check_circle_outline,
                                          size: 22),
                                  label: Text(
                                    localIsSaving ? 'Saving…' : 'Save',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Layer OSM langsung dari jaringan: dasar di bawah overlay PDF & cadangan
  /// bila overlay tak bisa ditampilkan.
  TileLayer _osmNetworkLayer() => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: ApiConfig.bundleName,
        tileProvider: NetworkTileProvider(),
      );

  // P0: Satu layer per tipe geometri, bukan satu layer per record
  List<Widget> _buildExistingDataLayers() {
    if (_existingData.isEmpty) return [];
    final layers = <Widget>[];

    switch (widget.project.geometryType) {
      case GeometryType.point:
        // P3: Cluster markers di zoom rendah, individual di zoom tinggi
        final markers = _getClusteredMarkers();
        if (markers.isNotEmpty) {
          layers.add(MarkerLayer(markers: markers));
        }
        break;

      case GeometryType.line:
        // 1 PolylineLayer + 1 MarkerLayer (tap targets)
        if (_visiblePolylines.isNotEmpty) {
          layers.add(PolylineLayer(polylines: _visiblePolylines));
        }
        if (_visibleMarkers.isNotEmpty) {
          layers.add(MarkerLayer(markers: _visibleMarkers));
        }
        break;

      case GeometryType.polygon:
        // 1 PolygonLayer + 1 MarkerLayer (tap targets)
        if (_visiblePolygons.isNotEmpty) {
          layers.add(PolygonLayer(polygons: _visiblePolygons));
        }
        if (_visibleMarkers.isNotEmpty) {
          layers.add(MarkerLayer(markers: _visibleMarkers));
        }
        break;
    }

    return layers;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        clipBehavior: Clip.none, // Agar shadow tidak terpotong
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () async {
              // Use didPopRoute logic for consistent behavior
              final canPop = !(await didPopRoute());
              if (canPop && mounted) {
                Navigator.pop(context);
              }
            },
            padding: EdgeInsets.zero,
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.white,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getGeometryIcon(),
                size: 18,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                widget.project.geometryType
                    .toString()
                    .split('.')
                    .last
                    .toUpperCase(),
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          // Connectivity Indicator (Status)
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.grey.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: const Center(
              child: ConnectivityIndicator(
                showLabel: false,
                iconSize: 20,
              ),
            ),
          ),
          // Location Provider Button
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                _locationService.currentProvider == LocationProvider.emlid
                    ? Icons.satellite_alt
                    : Icons.gps_fixed,
                size: 20,
                color:
                    _locationService.currentProvider == LocationProvider.emlid
                        ? (_locationService.isEmlidConnected &&
                                _locationService.isEmlidStreaming
                            ? Colors.blue
                            : Colors.orange)
                        : Colors.black87,
              ),
              padding: EdgeInsets.zero,
              tooltip: 'Location Provider Settings',
              onPressed: () async {
                // Navigate to Location Provider screen
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LocationProviderScreen(),
                  ),
                );

                // Reload if provider changed
                if (result == true && mounted) {
                  // Restart location stream with new provider
                  _startUnifiedLocationStream();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Location provider updated to ${_locationService.currentProvider.name}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
          // Save/Loading Button
          if (_isSaving)
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primaryColor),
                ),
              ),
            )
          else
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _canSaveData()
                    ? Colors.green // Hijau jika memenuhi syarat
                    : Colors.grey[300], // Abu-abu jika belum memenuhi syarat
                borderRadius: BorderRadius.circular(12),
                boxShadow: _canSaveData()
                    ? [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.green.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [], // Tidak ada shadow jika disabled
              ),
              child: IconButton(
                icon: Icon(
                  Icons.check,
                  size: 20,
                  color: _canSaveData()
                      ? Colors.white // Putih jika enabled
                      : Colors.grey[600], // Abu-abu tua jika disabled
                ),
                padding: EdgeInsets.zero,
                onPressed: _canSaveData()
                    ? () async {
                        // Konfirmasi hanya bila GPS/geometri perlu dicek.
                        final ok = await _confirmBeforeForm();
                        if (!ok || !mounted) return;
                        _showFormBottomSheet();
                      }
                    : null,
                tooltip: _getConfirmTooltip(),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          _buildMap(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Stack(children: [
      // Map full screen tanpa SafeArea untuk transparency penuh
      Positioned.fill(
        top: 0,
        bottom: 0,
        child: ClipRect(
          child: Builder(
            builder: (context) {
              // Show loading overlay when getting location
              if (_isLoadingLocation) {
                return Container(
                  color: Colors.white,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Getting your location...',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ClipRect(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedBasemap?.type == BasemapType.pdf &&
                            _selectedBasemap!.hasPdfGeoreferencing
                        ? LatLng(
                            (_selectedBasemap!.pdfMinLat! +
                                    _selectedBasemap!.pdfMaxLat!) /
                                2,
                            (_selectedBasemap!.pdfMinLon! +
                                    _selectedBasemap!.pdfMaxLon!) /
                                2,
                          )
                        : (_currentLocation != null
                            ? LatLng(_currentLocation!.latitude,
                                _currentLocation!.longitude)
                            : const LatLng(-6.2088, 106.8456)),
                    initialZoom: _selectedBasemap?.type == BasemapType.pdf &&
                            _selectedBasemap!.hasPdfGeoreferencing
                        ? 13 // PDF basemap: zoom level yang reasonable
                        : 15, // Non-PDF: zoom lebih tinggi ke user location
                    onTap: (pos, latlng) {
                      // Alat ukur menyita tap saat aktif; jika tidak, perilaku lama.
                      if (handleMapToolsTap(latlng)) return;
                      _onMapTap(pos, latlng);
                    },
                    onPositionChanged: (position, hasGesture) {
                      _currentZoom = position.zoom;
                      // Notifier, bukan setState: label koordinat crosshair
                      // saja yang ikut berubah tiap frame geser peta.
                      _centerNotifier.value = position.center;
                      // P2: debounce culling 200ms agar tidak terlalu sering
                      _cullingDebounce?.cancel();
                      _cullingDebounce = Timer(
                        const Duration(milliseconds: 200),
                        _updateVisibleLayers,
                      );
                    },
                  ),
                  children: [
                    // Basemap Layer - Support both Tile and Overlay modes.
                    // Tanpa I/O: overlay PDF disiapkan _pdfOverlay saat ganti.
                    if (_selectedBasemap != null)
                      ...buildBasemapLayers(
                        _selectedBasemap!,
                        overlay: _pdfOverlay.spec,
                        fallback: _osmNetworkLayer,
                      )
                    else
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: ApiConfig.bundleName,
                        tileProvider: SqliteCachedTileProvider(
                          basemapId: 'osm_road',
                          maxStale: const Duration(days: 30),
                        ),
                      ),

                    // GeoJSON Layers (user-imported) — dibangun sekali saat
                    // layer berubah, bukan tiap frame.
                    ..._geoJsonLayerWidgets,

                    // Existing Data Layers (from project)
                    ..._buildExistingDataLayers(),

                    // Collected Points Layers (currently being collected)
                    if (_collectedPoints.isNotEmpty) ...[
                      // Line/Polygon stroke
                      if (widget.project.geometryType == GeometryType.line ||
                          widget.project.geometryType == GeometryType.polygon)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _collectedPoints
                                  .map((p) => LatLng(p.latitude, p.longitude))
                                  .toList(),
                              color: widget.project.geometryType ==
                                      GeometryType.line
                                  ? _settingsService.settings.lineColor
                                  : _settingsService.settings.polygonColor,
                              strokeWidth: _settingsService.settings.lineWidth,
                            ),
                          ],
                        ),

                      // Polygon fill
                      if (widget.project.geometryType == GeometryType.polygon &&
                          _collectedPoints.length >= 3)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: _collectedPoints
                                  .map((p) => LatLng(p.latitude, p.longitude))
                                  .toList(),
                              color: _settingsService.settings.polygonColor
                                  .withOpacity(
                                      _settingsService.settings.polygonOpacity),
                              borderColor:
                                  _settingsService.settings.polygonColor,
                              borderStrokeWidth:
                                  _settingsService.settings.lineWidth,
                            ),
                          ],
                        ),

                      // Point markers: hanya first dan last
                      MarkerLayer(
                        markers: [
                          // First point
                          Marker(
                            point: LatLng(
                              _collectedPoints.first.latitude,
                              _collectedPoints.first.longitude,
                            ),
                            width: _settingsService.settings.pointSize * 2,
                            height: _settingsService.settings.pointSize * 2,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _settingsService.settings.pointColor,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Center(
                                child: Text(
                                  '1',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Last point (jika lebih dari 1)
                          if (_collectedPoints.length > 1)
                            Marker(
                              point: LatLng(
                                _collectedPoints.last.latitude,
                                _collectedPoints.last.longitude,
                              ),
                              width: _settingsService.settings.pointSize * 2,
                              height: _settingsService.settings.pointSize * 2,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors
                                      .red, // Last point tetap merah untuk dibedakan
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    '${_collectedPoints.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],

                    // Ring akurasi di sekitar posisi: radius = akurasi (meter),
                    // warna = confidence. Biru = fix bagus (recordable), amber =
                    // masih "acquiring"/tak layak rekam. Hanya layer ini (bukan
                    // seluruh layar) yang dibangun ulang per frame animasi/fix.
                    AnimatedBuilder(
                      animation: Listenable.merge(
                          [_markerAnimController, _locationNotifier]),
                      builder: (context, _) {
                        final pos = _animatedMarkerLatLng;
                        final loc = _currentLocation;
                        if (pos == null || loc == null) {
                          return const SizedBox.shrink();
                        }
                        final color =
                            loc.recordable ? Colors.blue : Colors.orange;
                        return CircleLayer(
                          circles: [
                            CircleMarker(
                              point: pos,
                              radius: (loc.accuracy ?? 15).clamp(0.5, 80.0),
                              useRadiusInMeter: true,
                              color: color.withOpacity(0.12),
                              borderColor: color.withOpacity(0.55),
                              borderStrokeWidth: 1.5,
                            ),
                          ],
                        );
                      },
                    ),

                    // Current Location Marker (User Location - Blue with direction)
                    // Marker lokasi user SELALU tampil (termasuk saat tracking).
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _markerAnimController,
                        _locationNotifier,
                        _bearingNotifier,
                      ]),
                      builder: (context, _) {
                        final pos = _animatedMarkerLatLng;
                        if (pos == null) return const SizedBox.shrink();
                        return MarkerLayer(
                          markers: [
                            Marker(
                              point: pos,
                              width: 60,
                              height: 60,
                              child: UserLocationMarker(
                                bearing: _bearingNotifier.value,
                                isEmlidGPS: _locationService.currentProvider ==
                                    LocationProvider.emlid,
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    // Map measure tool overlays (shared, scratch) — on top.
                    ...buildMapToolsLayers(),

                    // Overlay PDF sedang di-decode (ganti basemap).
                    if (_pdfOverlay.loading) const PdfOverlayLoadingChip(),
                  ],
                ),
              );
            },
          ),
          )
        ),

      // Center Crosshair Marker dengan koordinat (hanya muncul setelah loading selesai)
      if (!_isLoadingLocation)
        const Center(
          child: IgnorePointer(
            child: Padding(
                padding: EdgeInsets.only(top: 0), // geser ke bawah 16px
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    // Crosshair icon
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.location_searching,
                        size: 40,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                )),
          ),
        ),

      // Info Card Overlay (dengan padding top untuk status bar dan app bar)
      Positioned(
        top: MediaQuery.of(context).padding.top +
            kToolbarHeight +
            AppTheme.spacingSmall,
        left: AppTheme.spacingMedium,
        right: AppTheme.spacingMedium,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Info card mengikuti fix GPS lewat notifier (tanpa rebuild peta).
            ValueListenableBuilder<GeoPoint?>(
              valueListenable: _locationNotifier,
              builder: (context, _, __) => _buildInfoCard(),
            ),
            GpsStatusBanners(
              location: _locationNotifier,
              emlidStatus: _locationService.emlidStatus,
              usingEmlid:
                  _locationService.currentProvider == LocationProvider.emlid,
              isTracking: _isTracking,
              isPaused: _isPaused,
              lastEmlidDataTime: () => _locationService.lastEmlidDataTime,
            ),
            const SizedBox(height: 4),
            // Koordinat Crosshair
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.gps_fixed,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<LatLng>(
                    valueListenable: _centerNotifier,
                    builder: (context, c, _) => Text(
                      '${c.latitude.toStringAsFixed(6)}, ${c.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // ── RIGHT CONTROLS — satu kolom responsif (tak saling menumpuk) ──────
      MapControlsColumn(
        right: AppTheme.spacingMedium,
        bottom: (_isBottomSheetExpanded
                ? _getExpandedBottomSheetHeight()
                : _getCollapsedBottomSheetHeight()) +
            AppTheme.spacingLarge,
        children: [
          // Map measure tools — paling atas.
          buildMapToolsPanel(),

          // Compass — jarum mengikuti rotasi peta, reset ber-animasi
          CompassButton(mapController: _mapController, size: 44),

          // Mode Toggle (hanya line/polygon)
          if (widget.project.geometryType != GeometryType.point)
            MapToolButton(
              // Saat tracking berjalan, ganti mode dinonaktifkan (dulu diam-diam
              // menghentikan tracking).
              tooltip: _isTracking
                  ? 'Stop tracking to switch mode'
                  : (_collectionMode == CollectionMode.drawing
                      ? 'Switch to GPS / crosshair mode'
                      : 'Switch to drawing mode (tap map to add points)'),
              active: _collectionMode == CollectionMode.drawing,
              icon: _collectionMode == CollectionMode.drawing
                  ? Icons.touch_app
                  : Icons.edit,
              onPressed: _isTracking
                  ? () => showInfoFeedback(
                      context, 'Stop tracking first to switch mode.',
                      warning: true)
                  : () {
                      setState(() {
                        _collectionMode =
                            _collectionMode == CollectionMode.tracking
                                ? CollectionMode.drawing
                                : CollectionMode.tracking;
                      });
                      HapticFeedback.selectionClick();
                    },
            ),

          // Layers Panel (badge = jumlah layer aktif)
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
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${_layers.where((l) => l.isActive).length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                : null,
          ),

          // Offline Download
          MapToolButton(
            tooltip: 'Download for Offline',
            icon: Icons.download,
            iconColor: Colors.green,
            onPressed: _showOfflineDownloadDialog,
          ),

          // Basemap Selector
          MapToolButton(
            tooltip: 'Basemap',
            icon: Icons.map_outlined,
            onPressed: _showBasemapSelector,
          ),

          // Zoom to User Location
          MapToolButton(
            tooltip: 'My Location',
            icon: Icons.my_location,
            onPressed: () {
              if (_currentLocation != null) {
                _mapController.move(
                  LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
                  _mapController.camera.zoom, // preserve current zoom, never zoom out
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Location not available'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    ]);
  }

  /// Kartu status di atas peta. Teks penting (akurasi, kualitas fix, jumlah
  /// titik) ≥ 13 sp agar terbaca di bawah terik matahari (dulu 8–10 px).
  Widget _buildInfoCard() {
    double? distance;
    double? area;

    if (_collectedPoints.length >= 2) {
      if (widget.project.geometryType == GeometryType.line) {
        distance = _locationService.calculateLineDistance(_collectedPoints);
      } else if (widget.project.geometryType == GeometryType.polygon &&
          _collectedPoints.length >= 3) {
        area = _locationService.calculatePolygonArea(_collectedPoints);
      }
    }

    final loc = _currentLocation;
    final isEmlid = _locationService.currentProvider == LocationProvider.emlid;
    final acc = loc?.accuracy;
    final meetsReq =
        loc != null && _locationService.pointMeetsCurrentRequirement(loc);
    final accColor = loc == null
        ? Colors.grey.shade600
        : (meetsReq ? Colors.green.shade700 : Colors.orange.shade800);
    final accText = acc == null
        ? '± — m'
        : '±${acc < 1 ? acc.toStringAsFixed(2) : acc.toStringAsFixed(1)} m';

    final drawing = _collectionMode == CollectionMode.drawing;
    final statusText = drawing
        ? 'Drawing mode'
        : _isTracking
            ? (_isPaused ? 'Paused' : 'Tracking')
            : (_session?.pendingSave ?? false)
                ? 'Stopped — not saved yet'
                : 'Ready';
    final statusIcon = drawing
        ? Icons.edit
        : _isTracking
            ? (_isPaused ? Icons.pause_circle : Icons.fiber_manual_record)
            : Icons.gps_not_fixed;
    final statusColor = drawing
        ? AppTheme.primaryColor
        : _isTracking
            ? (_isPaused ? Colors.orange : Colors.red)
            : Colors.grey.shade700;

    final quality = isEmlid
        ? 'RTK ${(loc?.fixQuality ?? (_locationService.isEmlidConnected ? '…' : 'OFF')).toUpperCase()}'
        : 'Phone GPS';
    final qualityColor = isEmlid
        ? (loc?.fixQuality != null
            ? _getFixQualityColor(loc!.fixQuality!)
            : Colors.orange.shade800)
        : Colors.blueGrey.shade600;

    return Container(
      decoration: AppTheme.getCardDecoration.copyWith(
        color: Colors.white.withOpacity(0.96),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Baris 1: status & jumlah titik
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_collectedPoints.length} '
                    'point${_collectedPoints.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Baris 2: akurasi besar + sumber/kualitas + panjang/luas
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  accText,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: accColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: qualityColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    quality,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (distance != null)
                  Expanded(
                    child: Text(
                      _settingsService.settings.formatDistance(distance),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else if (area != null)
                  Expanded(
                    child: Text(
                      _settingsService.settings.formatArea(area),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),

            // Drawing mode hint
            if (drawing) ...[
              const SizedBox(height: 4),
              Text(
                'Tap the map to add points',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getFixQualityColor(String fixQuality) {
    switch (fixQuality.toLowerCase()) {
      case 'fix':
        return Colors.green;
      case 'float':
        return Colors.orange;
      case 'autonomous':
      case 'dgps':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildImageErrorWidget() {
    return Container(
      height: 250,
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load image',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The image file may be corrupted',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageNotFoundWidget(String path) {
    return Container(
      height: 250,
      color: Colors.orange[50],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_not_supported_rounded,
                size: 64,
                color: Colors.orange[400],
              ),
              const SizedBox(height: 12),
              Text(
                'Image file not found',
                style: TextStyle(
                  color: Colors.orange[800],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                path,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _getExpandedBottomSheetHeight() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return BottomControlsMetrics.expanded(
            widget.project.geometryType, _collectionMode) +
        bottomPadding;
  }

  double _getCollapsedBottomSheetHeight() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return BottomControlsMetrics.collapsed + bottomPadding;
  }

  Widget _buildBottomControls() {
    return CollapsibleBottomControls(
      isExpanded: _isBottomSheetExpanded,
      onToggleExpanded: () {
        setState(() {
          _isBottomSheetExpanded = !_isBottomSheetExpanded;
        });
      },
      geometryType: widget.project.geometryType,
      collectionMode: _collectionMode,
      isTracking: _isTracking,
      isPaused: _isPaused,
      collectedPoints: _collectedPoints,
      onToggleTracking: _toggleTracking,
      onTogglePause: _togglePause,
      onAddPoint: _addCurrentPoint,
      onUndoPoint: _undoLastPoint,
      onClearPoints: _clearPoints,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Layers Panel Sheet – toggle GeoJSON layers on/off from map
// ═══════════════════════════════════════════════════════════

class _LayersPanelSheet extends StatefulWidget {
  final List<LayerModel> layers;
  final Future<void> Function(LayerModel, bool) onToggle;

  const _LayersPanelSheet({
    required this.layers,
    required this.onToggle,
  });

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

  Color _geomColor(String type) {
    switch (type) {
      case 'Point':
      case 'MultiPoint':
        return Colors.red;
      case 'LineString':
      case 'MultiLineString':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  IconData _geomIcon(String type) {
    switch (type) {
      case 'Point':
      case 'MultiPoint':
        return Icons.place;
      case 'LineString':
      case 'MultiLineString':
        return Icons.timeline;
      default:
        return Icons.crop_square;
    }
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
      maxChildSize: 0.85,
      minChildSize: 0.25,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        Text(
                          '${_layers.where((l) => l.isActive).length} of ${_layers.length} active',
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
            // List
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
                          const SizedBox(height: 4),
                          Text('Import GeoJSON layers from the Layers menu',
                              style: TextStyle(
                                  color: Colors.grey[400], fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: _layers.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (_, i) {
                        final layer = _layers[i];
                        final isLoading =
                            _loading[layer.id] == true;
                        final color = layer.style.fillColor;
                        final geomColor = _geomColor(layer.geometryType);

                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: color.withOpacity(0.5),
                                  width: 2),
                            ),
                            child: Icon(
                              _geomIcon(layer.geometryType),
                              color: color,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            layer.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: layer.isActive
                                  ? Colors.black87
                                  : Colors.grey[500],
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color:
                                      geomColor.withOpacity(0.1),
                                  borderRadius:
                                      BorderRadius.circular(3),
                                ),
                                child: Text(
                                  layer.geometryType.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: geomColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (layer.labelField != null) ...
                                [
                                  const SizedBox(width: 6),
                                  Icon(Icons.label_outline,
                                      size: 11,
                                      color: Colors.grey[500]),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      layer.labelField!,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[500]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                            ],
                          ),
                          trailing: isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.teal,
                                  ),
                                )
                              : Switch(
                                  value: layer.isActive,
                                  activeColor: Colors.teal,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (v) => _toggle(layer, v),
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
