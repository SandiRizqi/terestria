import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geoform_app/config/api_config.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

import '../../models/basemap_model.dart';
import '../../models/layer_model.dart';
import '../../services/basemap_service.dart';
import '../../services/layer_service.dart';
import '../../services/tile_providers/sqlite_cached_tile_provider.dart';
import '../../theme/app_theme.dart';
import '../basemap/basemap_management_screen.dart';
import 'dart:async';
import '../../services/settings_service.dart';
import '../../models/settings/app_settings.dart';
import '../../services/location_service_v2.dart';
import '../../models/geo_data_model.dart';
import '../data_collection/widgets/user_location_marker.dart';

/// Fullscreen map viewer for notification GeoJSON data.
/// Supports basemap switching, user GeoJSON layers, click-to-inspect, and notification overlay.
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

class _NotificationMapScreenState extends State<NotificationMapScreen> {
  final MapController _mapController = MapController();
  final BasemapService _basemapService = BasemapService();
  final LayerService _layerService = LayerService();

  Basemap? _selectedBasemap;
  List<LayerModel> _layers = [];
  final Map<String, Map<String, dynamic>> _layerGeoJsonCache = {};

  final SettingsService _settingsService = SettingsService();
  final LocationServiceV2 _locationService = LocationServiceV2();

  GeoPoint? _currentLocation;
  StreamSubscription<GeoPoint>? _locationSubscription;

  Map<String, dynamic>? _notificationGeoJson;
  bool _isLoading = true;
  String? _parseError;

  // Map rotation for compass
  double _currentBearing = 0;
  LatLng _centerCoordinates = const LatLng(-6.2088, 106.8456);

  // Selected feature properties (click-to-inspect)
  Map<String, dynamic>? _selectedProperties;
  String? _selectedGeometryType;
  LatLng? _selectedLatLng;

  // Waypoint Navigation
  LatLng? _navigationTarget;
  String? _navigationLabel;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _settingsService.initialize();

    // Parse GeoJSON (offline-safe)
    try {
      _notificationGeoJson =
          jsonDecode(widget.geoJsonData) as Map<String, dynamic>;
    } catch (e) {
      _parseError = 'Gagal parse GeoJSON: $e';
    }

    // Load basemap + layers (offline-safe, uses local SQLite cache)
    await Future.wait([
      _loadBasemap(),
      _loadActiveLayers(),
    ]);

    if (mounted) {
      setState(() => _isLoading = false);

      if (_notificationGeoJson != null && _parseError == null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _fitToNotificationBounds();
        });
      }
    }

    // Fire-and-forget: location is NOT blocking the map
    _initLocation();
  }

  /// Initialize location separately so map renders even without GPS/signal.
  void _initLocation() async {
    try {
      await _locationService.initialize();
      await _locationService.loadLocationSettings();
    } catch (e) {
      print('Location init failed (offline?): $e');
      return; // Map still works without location
    }

    // One-shot location
    try {
      final loc = await _locationService.getCurrentLocation();
      if (loc != null && mounted) {
        setState(() => _currentLocation = loc);
      }
    } catch (e) {
      print('One-shot location failed: $e');
    }

    // Continuous updates
    _locationSubscription = _locationService.getActiveLocationStream().listen(
      (GeoPoint loc) {
        if (mounted) {
          setState(() => _currentLocation = loc);
        }
      },
      onError: (e) {
        print('Location stream error: $e');
      },
    );
  }

  Future<void> _loadBasemap() async {
    final basemap = await _basemapService.getSelectedBasemap();
    if (mounted) setState(() => _selectedBasemap = basemap);
  }

  Future<void> _loadActiveLayers() async {
    final layers = await _layerService.loadLayers();
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
      });
    }
  }

  Future<void> _toggleLayerActive(LayerModel layer, bool active) async {
    await _layerService.toggleLayer(layer.id, active);
    await _loadActiveLayers();
  }

  // ═══════════════════════════════════════════════════════════
  // Map Tap → find nearest feature and show properties
  // ═══════════════════════════════════════════════════════════

  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    if (_notificationGeoJson == null) return;

    final features =
        _notificationGeoJson!['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) return;

    // Find the nearest feature to the tap point
    Map<String, dynamic>? nearestProps;
    String? nearestType;
    double nearestDist = double.infinity;

    for (final f in features) {
      final feature = f as Map<String, dynamic>;
      final geom = feature['geometry'] as Map<String, dynamic>?;
      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      if (geom == null) continue;

      final type = geom['type'] as String? ?? '';
      final dist = _distanceToFeature(latlng, geom);

      if (dist < nearestDist) {
        nearestDist = dist;
        nearestProps = props;
        nearestType = type;
      }
    }

    // Threshold: ~500m at zoom 15 (rough degrees)
    final zoom = _mapController.camera.zoom;
    final threshold = 300 / math.pow(2, zoom); // adaptive threshold

    if (nearestProps != null && nearestDist < threshold) {
      // Find the representative coordinate of nearest feature
      LatLng? featureLatLng;
      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final props = feature['properties'] as Map<String, dynamic>? ?? {};
        if (props == nearestProps) {
          final geom = feature['geometry'] as Map<String, dynamic>?;
          if (geom != null) {
            featureLatLng = _getFeatureCentroid(geom);
          }
          break;
        }
      }
      setState(() {
        _selectedProperties = nearestProps;
        _selectedGeometryType = nearestType;
        _selectedLatLng = featureLatLng;
      });
    } else {
      // Dismiss popup if tapping empty area
      if (_selectedProperties != null) {
        setState(() {
          _selectedProperties = null;
          _selectedGeometryType = null;
          _selectedLatLng = null;
        });
      }
    }
  }

  LatLng? _getFeatureCentroid(Map<String, dynamic> geom) {
    final type = geom['type'] as String? ?? '';
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
        final mid = line[line.length ~/ 2];
        return LatLng((mid[1] as num).toDouble(), (mid[0] as num).toDouble());
      case 'Polygon':
        final ring = (coords as List)[0] as List;
        double latSum = 0, lngSum = 0;
        for (final c in ring) {
          latSum += (c[1] as num).toDouble();
          lngSum += (c[0] as num).toDouble();
        }
        return LatLng(latSum / ring.length, lngSum / ring.length);
      case 'MultiPolygon':
        final ring = ((coords as List).first as List).first as List;
        double latSum = 0, lngSum = 0;
        for (final c in ring) {
          latSum += (c[1] as num).toDouble();
          lngSum += (c[0] as num).toDouble();
        }
        return LatLng(latSum / ring.length, lngSum / ring.length);
      default:
        return null;
    }
  }

  double _distanceToFeature(LatLng tap, Map<String, dynamic> geom) {
    final type = geom['type'] as String? ?? '';
    final coords = geom['coordinates'];
    if (coords == null) return double.infinity;

    switch (type) {
      case 'Point':
        return _distToCoord(tap, coords as List<dynamic>);
      case 'MultiPoint':
        return (coords as List<dynamic>)
            .map((c) => _distToCoord(tap, c as List<dynamic>))
            .reduce(math.min);
      case 'LineString':
        return _distToLine(tap, coords as List<dynamic>);
      case 'MultiLineString':
        return (coords as List<dynamic>)
            .map((l) => _distToLine(tap, l as List<dynamic>))
            .reduce(math.min);
      case 'Polygon':
        return _distToPolygon(tap, coords as List<dynamic>);
      case 'MultiPolygon':
        return (coords as List<dynamic>)
            .map((p) => _distToPolygon(tap, p as List<dynamic>))
            .reduce(math.min);
      default:
        return double.infinity;
    }
  }

  double _distToCoord(LatLng tap, List<dynamic> coord) {
    final lng = (coord[0] as num).toDouble();
    final lat = (coord[1] as num).toDouble();
    return _haversineApprox(tap, LatLng(lat, lng));
  }

  double _distToLine(LatLng tap, List<dynamic> coords) {
    double min = double.infinity;
    for (final c in coords) {
      final d = _distToCoord(tap, c as List<dynamic>);
      if (d < min) min = d;
    }
    return min;
  }

  double _distToPolygon(LatLng tap, List<dynamic> rings) {
    double min = double.infinity;
    for (final ring in rings) {
      for (final c in ring as List<dynamic>) {
        final d = _distToCoord(tap, c as List<dynamic>);
        if (d < min) min = d;
      }
    }
    return min;
  }

  double _haversineApprox(LatLng a, LatLng b) {
    final dLat = (a.latitude - b.latitude).abs();
    final dLng = (a.longitude - b.longitude).abs();
    return math.sqrt(dLat * dLat + dLng * dLng); // degree-based approx
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
          basemap.pdfMinLat == null ||
          basemap.pdfMinLon == null ||
          basemap.pdfMaxLat == null ||
          basemap.pdfMaxLon == null ||
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
                bounds: bounds,
                imageProvider: FileImage(imageFile),
                opacity: 1.0,
                gaplessPlayback: true,
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
            maxStale: const Duration(days: 30),
          ),
        ),
      ];
    }
  }

  TileLayer _defaultTileLayer() => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: ApiConfig.bundleName,
      );

  // ═══════════════════════════════════════════════════════════
  // User GeoJSON layers rendering
  // ═══════════════════════════════════════════════════════════

  List<Widget> _buildUserGeoJsonLayers() {
    final result = <Widget>[];
    for (final layer in _layers) {
      if (!layer.isActive) continue;
      final geoJson = _layerGeoJsonCache[layer.id];
      if (geoJson == null) continue;

      final widgets = _renderGeoJson(
        geoJson,
        fillColor: layer.style.fillColor,
        fillOpacity: layer.style.fillOpacity,
        strokeColor: layer.style.strokeColor,
        strokeWidth: layer.style.strokeWidth,
        pointSize: layer.style.pointSize,
        labelField: layer.labelField,
      );
      result.addAll(widgets);
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // Notification GeoJSON rendering
  // ═══════════════════════════════════════════════════════════

  List<Widget> _buildNotificationGeoJsonLayers() {
    if (_notificationGeoJson == null) return [];

    final features = _notificationGeoJson!['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) return [];

    // Separate features by geometry type
    final pointFeatures = <dynamic>[];
    final lineFeatures = <dynamic>[];
    final polygonFeatures = <dynamic>[];

    for (final f in features) {
      final feature = f as Map<String, dynamic>;
      final geom = feature['geometry'] as Map<String, dynamic>?;
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

    // Render points with point settings
    if (pointFeatures.isNotEmpty) {
      result.addAll(_renderGeoJson(
        {'type': 'FeatureCollection', 'features': pointFeatures},
        fillColor: s.pointColor,
        fillOpacity: 1.0,
        strokeColor: s.pointColor,
        strokeWidth: 2.0,
        pointSize: s.pointSize,
      ));
    }

    // Render lines with line settings
    if (lineFeatures.isNotEmpty) {
      result.addAll(_renderGeoJson(
        {'type': 'FeatureCollection', 'features': lineFeatures},
        fillColor: s.lineColor,
        fillOpacity: 1.0,
        strokeColor: s.lineColor,
        strokeWidth: s.lineWidth,
        pointSize: s.pointSize,
      ));
    }

    // Render polygons with polygon settings
    if (polygonFeatures.isNotEmpty) {
      result.addAll(_renderGeoJson(
        {'type': 'FeatureCollection', 'features': polygonFeatures},
        fillColor: s.polygonColor,
        fillOpacity: s.polygonOpacity,
        strokeColor: s.polygonColor,
        strokeWidth: s.lineWidth,
        pointSize: s.pointSize,
      ));
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // Shared GeoJSON rendering engine
  // ═══════════════════════════════════════════════════════════

  List<Widget> _renderGeoJson(
    Map<String, dynamic> geoJson, {
    required Color fillColor,
    required double fillOpacity,
    required Color strokeColor,
    required double strokeWidth,
    required double pointSize,
    String? labelField,
  }) {
    final features = geoJson['features'] as List<dynamic>? ?? [];
    final polylines = <Polyline>[];
    final polygons = <Polygon>[];
    final markers = <Marker>[];
    final labelMarkers = <Marker>[];

    for (final f in features) {
      final feature = f as Map<String, dynamic>;
      final geom = feature['geometry'] as Map<String, dynamic>?;
      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      if (geom == null) continue;

      final type = geom['type'] as String? ?? '';
      final label = labelField != null ? props[labelField]?.toString() : null;

      switch (type) {
        case 'Point':
          final coords = geom['coordinates'] as List<dynamic>;
          final latlng = LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          );
          markers.add(_buildPointMarker(
              latlng, fillColor, fillOpacity, strokeColor, strokeWidth, pointSize));
          if (label != null) labelMarkers.add(_buildLabelMarker(latlng, label));
          break;

        case 'MultiPoint':
          for (final c in geom['coordinates'] as List<dynamic>) {
            final coords = c as List<dynamic>;
            final latlng = LatLng(
              (coords[1] as num).toDouble(),
              (coords[0] as num).toDouble(),
            );
            markers.add(_buildPointMarker(
                latlng, fillColor, fillOpacity, strokeColor, strokeWidth, pointSize));
            if (label != null) labelMarkers.add(_buildLabelMarker(latlng, label));
          }
          break;

        case 'LineString':
          final pts = _coordsToLatLng(geom['coordinates'] as List<dynamic>);
          if (pts.length >= 2) {
            polylines.add(Polyline(
              points: pts,
              color: strokeColor.withValues(alpha: fillOpacity),
              strokeWidth: strokeWidth,
            ));
            if (label != null) {
              labelMarkers.add(_buildLabelMarker(pts[pts.length ~/ 2], label));
            }
          }
          break;

        case 'MultiLineString':
          for (final line in geom['coordinates'] as List<dynamic>) {
            final pts = _coordsToLatLng(line as List<dynamic>);
            if (pts.length >= 2) {
              polylines.add(Polyline(
                points: pts,
                color: strokeColor.withValues(alpha: fillOpacity),
                strokeWidth: strokeWidth,
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
              color: fillColor.withValues(alpha: fillOpacity),
              borderColor: strokeColor,
              borderStrokeWidth: strokeWidth,
            ));
            if (label != null) {
              labelMarkers.add(_buildLabelMarker(_centroid(outer), label));
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
                color: fillColor.withValues(alpha: fillOpacity),
                borderColor: strokeColor,
                borderStrokeWidth: strokeWidth,
              ));
              if (label != null) {
                labelMarkers.add(_buildLabelMarker(_centroid(outer), label));
              }
            }
          }
          break;
      }
    }

    final result = <Widget>[];
    if (polylines.isNotEmpty) result.add(PolylineLayer(polylines: polylines));
    if (polygons.isNotEmpty) result.add(PolygonLayer(polygons: polygons));
    if (markers.isNotEmpty) result.add(MarkerLayer(markers: markers));
    if (labelMarkers.isNotEmpty) result.add(MarkerLayer(markers: labelMarkers));
    return result;
  }

  Marker _buildPointMarker(LatLng latlng, Color fill, double opacity,
      Color stroke, double strokeW, double size) {
    final markerSize = size * 2;
    return Marker(
      point: latlng,
      width: markerSize,
      height: markerSize,
      child: Container(
        decoration: BoxDecoration(
          color: fill.withValues(alpha: opacity),
          shape: BoxShape.circle,
          border: Border.all(
            color: stroke,
            width: strokeW.clamp(0.5, 3.0),
          ),
        ),
      ),
    );
  }

  Marker _buildLabelMarker(LatLng latlng, String label) {
    return Marker(
      point: latlng,
      width: 32,
      height: 32,
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 20,
        constraints: const BoxConstraints(maxWidth: 32),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
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

  LatLng _centroid(List<LatLng> points) {
    double sumLat = 0, sumLng = 0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }

  // ═══════════════════════════════════════════════════════════
  // Auto-fit to notification GeoJSON bounds
  // ═══════════════════════════════════════════════════════════

  void _fitToNotificationBounds() {
    if (_notificationGeoJson == null) return;

    final features =
        _notificationGeoJson!['features'] as List<dynamic>? ?? [];
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
      for (final c in coords) {
        processCoord(c as List<dynamic>);
      }
    }

    for (final f in features) {
      final geom =
          (f as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;

      final type = geom['type'] as String? ?? '';
      final coordinates = geom['coordinates'];
      if (coordinates == null) continue;

      switch (type) {
        case 'Point':
          processCoord(coordinates as List<dynamic>);
          break;
        case 'MultiPoint':
        case 'LineString':
          processCoords(coordinates as List<dynamic>);
          break;
        case 'MultiLineString':
        case 'Polygon':
          for (final ring in coordinates as List<dynamic>) {
            processCoords(ring as List<dynamic>);
          }
          break;
        case 'MultiPolygon':
          for (final poly in coordinates as List<dynamic>) {
            for (final ring in poly as List<dynamic>) {
              processCoords(ring as List<dynamic>);
            }
          }
          break;
      }
    }

    if (!hasCoords || !mounted) return;

    try {
      if (minLat == maxLat && minLng == maxLng) {
        minLat -= 0.005;
        maxLat += 0.005;
        minLng -= 0.005;
        maxLng += 0.005;
      }

      final bounds = LatLngBounds(
        LatLng(minLat, minLng),
        LatLng(maxLat, maxLng),
      );

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
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
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LayersPanelSheet(
        layers: _layers,
        onToggle: (layer, active) => _toggleLayerActive(layer, active),
      ),
    );
  }

  void _showBasemapSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BasemapSelectorSheet(
        currentBasemap: _selectedBasemap,
        onBasemapSelected: (basemap) async {
          await _basemapService.setSelectedBasemap(basemap.id);
          await _loadBasemap();
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Properties popup
  // ═══════════════════════════════════════════════════════════

  Widget _buildPropertiesPopup() {
    if (_selectedProperties == null) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 80, // leave room for FABs
      bottom: 16 + MediaQuery.of(context).padding.bottom,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getGeomIcon(_selectedGeometryType ?? ''),
                      color: Colors.deepOrange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Feature Properties',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.deepOrange[800],
                        ),
                      ),
                    ),
                    if (_selectedLatLng != null)
                      InkWell(
                        onTap: () {
                          final label = _selectedProperties?.values
                              .firstWhere((v) => v is String, orElse: () => null)
                              ?.toString();
                          _startNavigation(_selectedLatLng!, label);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
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
                      onTap: () =>
                          setState(() => _selectedProperties = null),
                      child: Icon(Icons.close,
                          size: 18, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              // Properties list
              Flexible(
                child: _selectedProperties!.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No properties',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 13)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _selectedProperties!.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey[200]),
                        itemBuilder: (_, i) {
                          final entry =
                              _selectedProperties!.entries.elementAt(i);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    entry.value?.toString() ?? 'null',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
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
      case 'Point':
      case 'MultiPoint':
        return Icons.place;
      case 'LineString':
      case 'MultiLineString':
        return Icons.timeline;
      case 'Polygon':
      case 'MultiPolygon':
        return Icons.crop_square;
      default:
        return Icons.map;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Export Data
  // ═══════════════════════════════════════════════════════════

  void _showExportDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Export Data',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Choose format to export',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 16),
              _buildExportTile(Icons.code, 'GeoJSON', '.geojson', Colors.green, () {
                Navigator.pop(ctx);
                _exportGeoJson();
              }),
              _buildExportTile(Icons.public, 'KML', '.kml', Colors.blue, () {
                Navigator.pop(ctx);
                _exportKML();
              }),
              _buildExportTile(Icons.folder_zip, 'Shapefile (ZIP)', '.zip', Colors.orange, () {
                Navigator.pop(ctx);
                _exportShapefile();
              }),
              _buildExportTile(Icons.table_chart, 'CSV', '.csv', Colors.purple, () {
                Navigator.pop(ctx);
                _exportCSV();
              }),
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
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('Export as $ext file', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _exportGeoJson() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.geojson');
      await file.writeAsString(widget.geoJsonData);
      await _shareFile(file, 'application/geo+json');
    } catch (e) {
      _showExportError(e.toString());
    }
  }

  Future<void> _exportKML() async {
    try {
      final geoJson = jsonDecode(widget.geoJsonData) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>? ?? [];

      final buffer = StringBuffer();
      buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
      buffer.writeln('<Document>');
      buffer.writeln('<name>${widget.title}</name>');

      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final geom = feature['geometry'] as Map<String, dynamic>?;
        final props = feature['properties'] as Map<String, dynamic>? ?? {};
        if (geom == null) continue;

        final type = geom['type'] as String? ?? '';
        final name = props.values.firstWhere((v) => v is String, orElse: () => 'Feature') ?? 'Feature';

        buffer.writeln('<Placemark>');
        buffer.writeln('<name>$name</name>');

        // Description from properties
        if (props.isNotEmpty) {
          buffer.writeln('<description><![CDATA[');
          for (final entry in props.entries) {
            buffer.writeln('${entry.key}: ${entry.value}');
          }
          buffer.writeln(']]></description>');
        }

        switch (type) {
          case 'Point':
            final coords = geom['coordinates'] as List;
            buffer.writeln('<Point><coordinates>${coords[0]},${coords[1]},${coords.length > 2 ? coords[2] : 0}</coordinates></Point>');
            break;
          case 'LineString':
            buffer.writeln('<LineString><coordinates>');
            for (final c in geom['coordinates'] as List) {
              buffer.write('${c[0]},${c[1]},${(c as List).length > 2 ? c[2] : 0} ');
            }
            buffer.writeln('</coordinates></LineString>');
            break;
          case 'Polygon':
            buffer.writeln('<Polygon><outerBoundaryIs><LinearRing><coordinates>');
            final rings = geom['coordinates'] as List;
            for (final c in rings[0] as List) {
              buffer.write('${c[0]},${c[1]},${(c as List).length > 2 ? c[2] : 0} ');
            }
            buffer.writeln('</coordinates></LinearRing></outerBoundaryIs></Polygon>');
            break;
          case 'MultiPoint':
            buffer.writeln('<MultiGeometry>');
            for (final coords in geom['coordinates'] as List) {
              buffer.writeln('<Point><coordinates>${coords[0]},${coords[1]},${(coords as List).length > 2 ? coords[2] : 0}</coordinates></Point>');
            }
            buffer.writeln('</MultiGeometry>');
            break;
          case 'MultiLineString':
            buffer.writeln('<MultiGeometry>');
            for (final line in geom['coordinates'] as List) {
              buffer.writeln('<LineString><coordinates>');
              for (final c in line as List) {
                buffer.write('${c[0]},${c[1]},${(c as List).length > 2 ? c[2] : 0} ');
              }
              buffer.writeln('</coordinates></LineString>');
            }
            buffer.writeln('</MultiGeometry>');
            break;
          case 'MultiPolygon':
            buffer.writeln('<MultiGeometry>');
            for (final poly in geom['coordinates'] as List) {
              buffer.writeln('<Polygon><outerBoundaryIs><LinearRing><coordinates>');
              final rings = poly as List;
              for (final c in rings[0] as List) {
                buffer.write('${c[0]},${c[1]},${(c as List).length > 2 ? c[2] : 0} ');
              }
              buffer.writeln('</coordinates></LinearRing></outerBoundaryIs></Polygon>');
            }
            buffer.writeln('</MultiGeometry>');
            break;
        }
        buffer.writeln('</Placemark>');
      }

      buffer.writeln('</Document>');
      buffer.writeln('</kml>');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.kml');
      await file.writeAsString(buffer.toString());
      await _shareFile(file, 'application/vnd.google-earth.kml+xml');
    } catch (e) {
      _showExportError(e.toString());
    }
  }

  Future<void> _exportShapefile() async {
    try {
      final geoJson = jsonDecode(widget.geoJsonData) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>? ?? [];
      if (features.isEmpty) {
        _showExportError('No features to export');
        return;
      }

      // Determine dominant geometry type
      String? dominantType;
      for (final f in features) {
        final geom = (f as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
        if (geom != null) {
          dominantType = geom['type'] as String?;
          break;
        }
      }

      // Collect all property keys
      final allKeys = <String>{};
      for (final f in features) {
        final props = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? {};
        allKeys.addAll(props.keys);
      }
      final fieldNames = allKeys.take(10).toList(); // Limit to 10 fields for DBF

      // Build CSV-like content as a simplified "shapefile" approach
      // For true shapefile binary format, we create a simplified version
      final csvBuffer = StringBuffer();
      csvBuffer.writeln('WKT,${fieldNames.join(',')}');

      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final geom = feature['geometry'] as Map<String, dynamic>?;
        final props = feature['properties'] as Map<String, dynamic>? ?? {};
        if (geom == null) continue;

        final wkt = _geomToWKT(geom);
        final values = fieldNames.map((k) {
          final v = props[k]?.toString() ?? '';
          return '"${v.replaceAll('"', '""')}"';
        }).join(',');
        csvBuffer.writeln('"$wkt",$values');
      }

      // Create PRJ content (WGS84)
      const prjContent = 'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]';

      // Create archive
      final archive = Archive();
      final csvBytes = csvBuffer.toString().codeUnits;
      final prjBytes = prjContent.codeUnits;
      final geojsonBytes = widget.geoJsonData.codeUnits;

      archive.addFile(ArchiveFile('export.csv', csvBytes.length, csvBytes));
      archive.addFile(ArchiveFile('export.prj', prjBytes.length, prjBytes));
      archive.addFile(ArchiveFile('export.geojson', geojsonBytes.length, geojsonBytes));

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        _showExportError('Failed to create ZIP');
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.zip');
      await file.writeAsBytes(zipData);
      await _shareFile(file, 'application/zip');
    } catch (e) {
      _showExportError(e.toString());
    }
  }

  String _geomToWKT(Map<String, dynamic> geom) {
    final type = geom['type'] as String? ?? '';
    final coords = geom['coordinates'];
    switch (type) {
      case 'Point':
        return 'POINT (${coords[0]} ${coords[1]})';
      case 'MultiPoint':
        final pts = (coords as List).map((c) => '${c[0]} ${c[1]}').join(', ');
        return 'MULTIPOINT ($pts)';
      case 'LineString':
        final pts = (coords as List).map((c) => '${c[0]} ${c[1]}').join(', ');
        return 'LINESTRING ($pts)';
      case 'MultiLineString':
        final lines = (coords as List).map((line) {
          final pts = (line as List).map((c) => '${c[0]} ${c[1]}').join(', ');
          return '($pts)';
        }).join(', ');
        return 'MULTILINESTRING ($lines)';
      case 'Polygon':
        final rings = (coords as List).map((ring) {
          final pts = (ring as List).map((c) => '${c[0]} ${c[1]}').join(', ');
          return '($pts)';
        }).join(', ');
        return 'POLYGON ($rings)';
      case 'MultiPolygon':
        final polys = (coords as List).map((poly) {
          final rings = (poly as List).map((ring) {
            final pts = (ring as List).map((c) => '${c[0]} ${c[1]}').join(', ');
            return '($pts)';
          }).join(', ');
          return '($rings)';
        }).join(', ');
        return 'MULTIPOLYGON ($polys)';
      default:
        return 'POINT (0 0)';
    }
  }

  Future<void> _exportCSV() async {
    try {
      final geoJson = jsonDecode(widget.geoJsonData) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>? ?? [];

      // Collect all property keys
      final allKeys = <String>{};
      for (final f in features) {
        final props = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? {};
        allKeys.addAll(props.keys);
      }
      final fieldNames = allKeys.toList();

      final buffer = StringBuffer();
      buffer.writeln('latitude,longitude,geometry_type,${fieldNames.join(',')}');

      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final geom = feature['geometry'] as Map<String, dynamic>?;
        final props = feature['properties'] as Map<String, dynamic>? ?? {};
        if (geom == null) continue;

        final type = geom['type'] as String? ?? '';
        final coords = geom['coordinates'];

        // Extract representative coordinate
        double lat = 0, lng = 0;
        switch (type) {
          case 'Point':
            lng = (coords[0] as num).toDouble();
            lat = (coords[1] as num).toDouble();
            break;
          case 'LineString':
            final mid = (coords as List)[coords.length ~/ 2];
            lng = (mid[0] as num).toDouble();
            lat = (mid[1] as num).toDouble();
            break;
          case 'Polygon':
            final ring = (coords as List)[0] as List;
            final mid = ring[ring.length ~/ 2];
            lng = (mid[0] as num).toDouble();
            lat = (mid[1] as num).toDouble();
            break;
          default:
            if (coords is List && coords.isNotEmpty) {
              final first = coords[0];
              if (first is List && first.isNotEmpty) {
                if (first[0] is num) {
                  lng = (first[0] as num).toDouble();
                  lat = (first[1] as num).toDouble();
                } else if (first[0] is List) {
                  lng = ((first[0] as List)[0] as num).toDouble();
                  lat = ((first[0] as List)[1] as num).toDouble();
                }
              }
            }
        }

        final values = fieldNames.map((k) {
          final v = props[k]?.toString() ?? '';
          return '"${v.replaceAll('"', '""')}"';
        }).join(',');

        buffer.writeln('$lat,$lng,"$type",$values');
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(buffer.toString());
      await _shareFile(file, 'text/csv');
    } catch (e) {
      _showExportError(e.toString());
    }
  }

  Future<void> _shareFile(File file, String mimeType) async {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: widget.title,
    );
  }

  void _showExportError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $message'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Waypoint Navigation
  // ═══════════════════════════════════════════════════════════

  void _startNavigation(LatLng target, String? label) {
    setState(() {
      _navigationTarget = target;
      _navigationLabel = label;
      _selectedProperties = null;
    });
  }

  void _stopNavigation() {
    setState(() {
      _navigationTarget = null;
      _navigationLabel = null;
    });
  }

  double _calcBearing(LatLng from, LatLng to) {
    final dLng = (to.longitude - from.longitude) * (math.pi / 180);
    final lat1 = from.latitude * (math.pi / 180);
    final lat2 = to.latitude * (math.pi / 180);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final bearing = math.atan2(y, x) * (180 / math.pi);
    return (bearing + 360) % 360;
  }

  double _calcDistance(LatLng from, LatLng to) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = (to.latitude - from.latitude) * (math.pi / 180);
    final dLng = (to.longitude - from.longitude) * (math.pi / 180);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(from.latitude * (math.pi / 180)) *
            math.cos(to.latitude * (math.pi / 180)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String _fmtDist(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String _bearingToCompass(double bearing) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((bearing + 22.5) % 360 / 45).floor();
    return dirs[idx];
  }

  Widget _buildNavigationOverlay() {
    if (_navigationTarget == null || _currentLocation == null) {
      return const SizedBox.shrink();
    }

    final userLatLng = LatLng(_currentLocation!.latitude, _currentLocation!.longitude);
    final distance = _calcDistance(userLatLng, _navigationTarget!);
    final bearing = _calcBearing(userLatLng, _navigationTarget!);
    final compassDir = _bearingToCompass(bearing);

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 80,
      left: 16,
      right: 80,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryGreen.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Direction arrow
                Transform.rotate(
                  angle: (bearing - _currentBearing) * (math.pi / 180),
                  child: const Icon(Icons.navigation, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _navigationLabel ?? 'Waypoint',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_fmtDist(distance)}  •  $compassDir (${bearing.toStringAsFixed(0)}°)',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                // Stop button
                InkWell(
                  onTap: _stopNavigation,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryGreen,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _parseError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text(
                          'Error Loading Map Data',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _parseError!,
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  top: false,
                  child: Stack(
                    children: [
                      // ── Map ──
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: const LatLng(-6.2088, 106.8456),
                          initialZoom: 5,
                          onTap: _onMapTap,
                          onPositionChanged: (position, hasGesture) {
                            if (position.center != null) {
                              if (_centerCoordinates.latitude != position.center!.latitude || 
                                  _centerCoordinates.longitude != position.center!.longitude) {
                                setState(() => _centerCoordinates = position.center!);
                              }
                            }
                            if (hasGesture) {
                              final bearing =
                                  _mapController.camera.rotation;
                              if (bearing != _currentBearing) {
                                setState(
                                    () => _currentBearing = bearing);
                              }
                            }
                          },
                        ),
                        children: [
                          if (_selectedBasemap != null)
                            ..._buildBasemapLayers(_selectedBasemap!)
                          else
                            _defaultTileLayer(),
                          ..._buildUserGeoJsonLayers(),
                          ..._buildNotificationGeoJsonLayers(),
                          if (_currentLocation != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(
                                    _currentLocation!.latitude,
                                    _currentLocation!.longitude,
                                  ),
                                  width: 60,
                                  height: 60,
                                  child: UserLocationMarker(
                                    bearing: _currentBearing,
                                    isEmlidGPS: _locationService.currentProvider ==
                                        LocationProvider.emlid,
                                  ),
                                ),
                              ],
                            ),
                          // Navigation target line + marker
                          if (_navigationTarget != null && _currentLocation != null)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: [
                                    LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
                                    _navigationTarget!,
                                  ],
                                  color: AppTheme.primaryGreen,
                                  strokeWidth: 2.5,
                                  pattern: StrokePattern.dashed(segments: [10, 8]),
                                ),
                              ],
                            ),
                        ],
                      ),

                      // Center Crosshair Marker
                      const Center(
                        child: IgnorePointer(
                          child: Icon(
                            Icons.location_searching,
                            size: 40,
                            color: Colors.black87,
                          ),
                        ),
                      ),

                      // Coordinates Crosshair Overlay (top center)
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
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
                                Text(
                                  '${_centerCoordinates.latitude.toStringAsFixed(6)}, ${_centerCoordinates.longitude.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'monospace',
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // 1.5. Zoom to User Location (bottom left)
                      Positioned(
                        bottom: bottomPadding + 16,
                        left: 16,
                        child: FloatingActionButton(
                          heroTag: 'userLocationMap',
                          mini: true,
                          backgroundColor: Colors.white,
                          elevation: 6,
                          child: const Icon(Icons.my_location, color: AppTheme.primaryColor),
                          onPressed: () {
                            if (_currentLocation != null) {
                              _mapController.move(
                                LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
                                17,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Zoomed to your location'),
                                  duration: Duration(seconds: 1),
                                ),
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
                      ),

                      // Export FAB (left side, above My Location)
                      Positioned(
                        bottom: bottomPadding + 76,
                        left: 16,
                        child: FloatingActionButton(
                          heroTag: 'export_data',
                          mini: true,
                          backgroundColor: Colors.white,
                          elevation: 6,
                          onPressed: _showExportDialog,
                          child: const Icon(Icons.ios_share, color: Colors.deepPurple),
                        ),
                      ),

                      // ── Right-side FABs (bottom to top) ──

                      // 1. Fit Bounds (bottom)
                      Positioned(
                        bottom: bottomPadding + 16,
                        right: 16,
                        child: FloatingActionButton(
                          heroTag: 'fit_bounds',
                          mini: true,
                          backgroundColor: Colors.white,
                          elevation: 6,
                          onPressed: _fitToNotificationBounds,
                          child: Icon(Icons.center_focus_strong,
                              color: AppTheme.primaryGreen),
                        ),
                      ),

                      // 2. Basemap selector
                      Positioned(
                        bottom: bottomPadding + 76,
                        right: 16,
                        child: FloatingActionButton(
                          heroTag: 'basemap',
                          mini: true,
                          backgroundColor: Colors.white,
                          elevation: 6,
                          onPressed: _showBasemapSelector,
                          child: const Icon(Icons.map_outlined,
                              color: AppTheme.primaryColor),
                        ),
                      ),

                      // 3. Layers panel
                      Positioned(
                        bottom: bottomPadding + 136,
                        right: 16,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            FloatingActionButton(
                              heroTag: 'geojson_layers',
                              mini: true,
                              backgroundColor:
                                  _layers.any((l) => l.isActive)
                                      ? Colors.teal
                                      : Colors.white,
                              elevation: 6,
                              tooltip: 'GeoJSON Layers',
                              onPressed: _showLayersPanel,
                              child: Icon(
                                Icons.layers_outlined,
                                color:
                                    _layers.any((l) => l.isActive)
                                        ? Colors.white
                                        : Colors.teal,
                              ),
                            ),
                            if (_layers.any((l) => l.isActive))
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
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
                                          fontWeight:
                                              FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // 4. Compass / Auto-North (top of FAB column)
                      Positioned(
                        bottom: bottomPadding + 196,
                        right: 16,
                        child: GestureDetector(
                          onTap: () {
                            _mapController.rotate(0);
                            setState(() => _currentBearing = 0);
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Transform.rotate(
                              angle: -_currentBearing *
                                  (math.pi / 180),
                              child: CustomPaint(
                                size: const Size(40, 40),
                                painter: _CompassPainter(),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ── Properties popup ──
                      _buildPropertiesPopup(),

                      // ── Navigation overlay ──
                      _buildNavigationOverlay(),
                    ],
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Compass Painter (same as data_collection)
// ═══════════════════════════════════════════════════════════

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // North needle (red)
    final northPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    final northPath = Path()
      ..moveTo(cx, cy - r * 0.68)
      ..lineTo(cx - r * 0.18, cy)
      ..lineTo(cx, cy - r * 0.12)
      ..lineTo(cx + r * 0.18, cy)
      ..close();
    canvas.drawPath(northPath, northPaint);

    // South needle (grey)
    final southPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.fill;
    final southPath = Path()
      ..moveTo(cx, cy + r * 0.68)
      ..lineTo(cx - r * 0.18, cy)
      ..lineTo(cx, cy + r * 0.12)
      ..lineTo(cx + r * 0.18, cy)
      ..close();
    canvas.drawPath(southPath, southPaint);

    // Center circle
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.12,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.12,
      Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // "N" label
    final tp = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.red,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(cx - tp.width / 2, cy - r * 0.68 - tp.height - 1),
    );
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
        decoration: BoxDecoration(
          color: AppTheme.scaffoldBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
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
                          '${_layers.where((l) => l.isActive).length} of ${_layers.length} active',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
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
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: _layers.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (_, i) {
                        final layer = _layers[i];
                        final isLoading = _loading[layer.id] == true;
                        final color = layer.style.fillColor;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: color.withValues(alpha: 0.5),
                                  width: 2),
                            ),
                            child: Icon(
                              layer.geometryIcon,
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
                          subtitle: Text(
                            layer.geometryType.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[500]),
                          ),
                          trailing: isLoading
                              ? const SizedBox(
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

// ═══════════════════════════════════════════════════════════
// Basemap Selector Sheet
// ═══════════════════════════════════════════════════════════

class _BasemapSelectorSheet extends StatefulWidget {
  final Basemap? currentBasemap;
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
  List<Basemap> _basemaps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBasemaps();
  }

  Future<void> _loadBasemaps() async {
    final basemaps = await _basemapService.getBasemaps();
    setState(() {
      _basemaps = basemaps;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.scaffoldBackground, // Premium theme background
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Select Basemap',
                    style: Theme.of(context).textTheme.titleLarge),
                TextButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('Manage'),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BasemapManagementScreen(),
                      ),
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
                  itemCount: _basemaps.length,
                  itemBuilder: (context, index) {
                    final basemap = _basemaps[index];
                    final isSelected =
                        widget.currentBasemap?.id == basemap.id;
                    return ListTile(
                      leading: Icon(Icons.map,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.grey),
                      title: Text(basemap.name,
                          style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                      subtitle: Text(
                          basemap.type == BasemapType.builtin
                              ? 'Built-in'
                              : 'Custom',
                          style: const TextStyle(fontSize: 12)),
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
