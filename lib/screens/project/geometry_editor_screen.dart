import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/api_config.dart';
import '../../models/basemap_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../../services/basemap/pdf_overlay_controller.dart';
import '../../services/basemap_service.dart';
import '../../services/geometry_edit.dart';
import '../../services/geometry_validation.dart';
import '../../services/location_service_v2.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/ui_feedback.dart';
import '../../widgets/map/basemap_layers.dart';

/// Koreksi geometri record dengan crosshair: pilih vertex (ketuk titiknya
/// atau ◀ ▶), geser peta agar crosshair di posisi benar, lalu "Move here",
/// "Insert after", atau "Delete". Mengembalikan titik baru, atau null bila
/// tak ada perubahan / dibatalkan.
class GeometryEditorScreen extends StatefulWidget {
  final GeometryType type;
  final List<GeoPoint> points;
  final String? title;

  /// Untuk test: jangan muat tile/basemap dari jaringan/disk.
  final bool showBasemap;

  const GeometryEditorScreen({
    super.key,
    required this.type,
    required this.points,
    this.title,
    this.showBasemap = true,
  });

  @override
  State<GeometryEditorScreen> createState() => _GeometryEditorScreenState();
}

class _GeometryEditorScreenState extends State<GeometryEditorScreen> {
  late final GeometryEditSession _session =
      GeometryEditSession(widget.type, widget.points);
  final MapController _map = MapController();
  final PdfOverlayController _pdfOverlay = PdfOverlayController();
  Basemap? _basemap;
  bool _locating = false;

  /// Di atas jumlah ini vertex digambar sebagai titik kecil tanpa nomor.
  static const _numberedLimit = 60;

  @override
  void initState() {
    super.initState();
    _pdfOverlay.addListener(_onOverlay);
    if (widget.showBasemap) _loadBasemap();
  }

  @override
  void dispose() {
    _pdfOverlay
      ..removeListener(_onOverlay)
      ..dispose();
    super.dispose();
  }

  void _onOverlay() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBasemap() async {
    try {
      final b = await BasemapService().getSelectedBasemap();
      if (!mounted) return;
      setState(() => _basemap = b);
      _pdfOverlay.show(b);
    } catch (e, st) {
      logWarn('Geometry editor: basemap not available',
          tag: 'EDIT', error: e, stack: st);
    }
  }

  LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

  void _update(VoidCallback change, {bool haptic = true}) {
    setState(change);
    if (haptic) HapticFeedback.selectionClick();
  }

  void _select(int index, {bool center = true}) {
    _update(() => _session.select(index), haptic: false);
    if (center) _centerOnSelected();
  }

  void _centerOnSelected() {
    final p = _session.selectedPoint;
    if (p == null) return;
    try {
      _map.move(_ll(p), _map.camera.zoom);
    } catch (_) {}
  }

  LatLng get _crosshair => _map.camera.center;

  void _moveHere() {
    final c = _crosshair;
    final moved = _session.moveSelectedTo(c.latitude, c.longitude);
    if (moved) {
      _update(() {});
    } else {
      showInfoFeedback(context,
          'The crosshair is already on this vertex. Pan the map first.',
          duration: const Duration(seconds: 2));
    }
  }

  void _insert() {
    final c = _crosshair;
    if (_session.insertAfterSelected(c.latitude, c.longitude)) {
      _update(() {});
    }
  }

  void _delete() {
    if (_session.deleteSelected()) {
      _update(() {});
      _centerOnSelected();
    } else {
      showInfoFeedback(
          context,
          'A ${widget.type.name} needs at least '
          '${GeometryEditSession.minPoints(widget.type)} points.',
          warning: true);
    }
  }

  void _undo() {
    if (_session.undo()) _update(() {});
  }

  Future<void> _goToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final loc = await LocationServiceV2().getCurrentLocation();
      if (!mounted) return;
      if (loc == null) {
        showInfoFeedback(context,
            'No GPS fix yet. Go outdoors and try again.', warning: true);
      } else {
        _map.move(_ll(loc), math.max(_map.camera.zoom, 18));
      }
    } catch (e, st) {
      if (mounted) {
        showErrorFeedback(context, 'Could not get your location',
            error: e, stack: st, tag: 'EDIT');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Ketuk peta: pilih vertex terdekat dalam ±32 px.
  void _onMapTap(TapPosition _, LatLng at) {
    final zoom = _map.camera.zoom;
    final metersPerPixel = 156543.03392 *
        math.cos(at.latitude * math.pi / 180) /
        math.pow(2, zoom);
    final i = _session.nearestVertex(at.latitude, at.longitude,
        maxMeters: math.max(1, metersPerPixel * 32));
    if (i != null) _select(i, center: false);
  }

  Future<void> _finish() async {
    if (!_session.isDirty) {
      Navigator.pop(context);
      return;
    }
    final points = _session.points;
    final warnings = geometryWarnings(widget.type, points);
    if (warnings.isNotEmpty) {
      final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded,
              color: Colors.orange.shade800, size: 32),
          title: const Text('Check the geometry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $w'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Use anyway'),
            ),
          ],
        ),
      );
      if (save != true || !mounted) return;
    }
    logInfo(
        'Geometry edited: ${widget.points.length} → ${points.length} '
        'vertices (${widget.type.name})',
        tag: 'EDIT');
    Navigator.pop(context, points);
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard geometry changes?'),
        content: const Text('Your changes to the points will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  void _showVertexList() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => ListView.builder(
          controller: scroll,
          itemCount: _session.length,
          itemBuilder: (ctx, i) {
            final p = _session.points[i];
            final selected = _session.selected == i;
            return ListTile(
              selected: selected,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor:
                    selected ? Colors.orange.shade800 : AppTheme.primaryColor,
                child: Text('${i + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              title: Text(
                  '${p.latitude.toStringAsFixed(6)}, '
                  '${p.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontFeatures: [
                    FontFeature.tabularFigures(),
                  ])),
              subtitle: Text(p.accuracy == null
                  ? 'Placed manually'
                  : 'GPS ±${p.accuracy!.toStringAsFixed(1)} m'
                      '${p.fixQuality == null ? '' : ' · ${p.fixQuality!.toUpperCase()}'}'),
              onTap: () {
                Navigator.pop(ctx);
                _select(i);
              },
            );
          },
        ),
      ),
    );
  }

  List<Widget> _geometryLayers() {
    final pts = _session.points.map(_ll).toList();
    final original = widget.points.map(_ll).toList();
    final showOriginal = _session.isDirty && original.length > 1;
    return [
      if (showOriginal)
        PolylineLayer(polylines: [
          Polyline(
            points: widget.type == GeometryType.polygon
                ? [...original, original.first]
                : original,
            color: Colors.grey.shade700.withOpacity(0.7),
            strokeWidth: 2,
            pattern: StrokePattern.dashed(segments: const [8, 6]),
          ),
        ]),
      if (widget.type == GeometryType.polygon && pts.length >= 3)
        PolygonLayer(polygons: [
          Polygon(
            points: pts,
            color: AppTheme.primaryColor.withOpacity(0.18),
            borderColor: AppTheme.primaryColor,
            borderStrokeWidth: 3,
          ),
        ])
      else if (widget.type != GeometryType.point && pts.length >= 2)
        PolylineLayer(polylines: [
          Polyline(points: pts, color: AppTheme.primaryColor, strokeWidth: 4),
        ]),
      MarkerLayer(markers: [
        for (var i = 0; i < pts.length; i++)
          if (i != _session.selected) _vertexMarker(i, pts[i], selected: false),
        if (_session.selected != null)
          _vertexMarker(_session.selected!, pts[_session.selected!],
              selected: true),
      ]),
    ];
  }

  Marker _vertexMarker(int i, LatLng at, {required bool selected}) {
    final numbered = selected || _session.length <= _numberedLimit;
    final size = selected ? 36.0 : (numbered ? 26.0 : 12.0);
    return Marker(
      point: at,
      width: selected ? 44 : math.max(size, 28),
      height: selected ? 44 : math.max(size, 28),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(i, center: false),
        child: Center(
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.orange.shade800 : AppTheme.primaryColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 3),
              ],
            ),
            child: numbered
                ? Text('${i + 1}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: selected ? 13 : 11,
                        fontWeight: FontWeight.w700))
                : null,
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final isPoint = widget.type == GeometryType.point;
    final sel = _session.selected;
    final p = _session.selectedPoint;
    final status = sel == null
        ? 'Tap a point to select it'
        : isPoint
            ? 'Move the map so the crosshair is on the correct spot'
            : 'Point ${sel + 1} of ${_session.length}'
                '${p?.accuracy == null ? ' · placed manually' : ' · GPS ±${p!.accuracy!.toStringAsFixed(1)} m'}';
    final button = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size(0, 50)),
    );
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (!isPoint)
                    IconButton(
                      tooltip: 'Previous point',
                      onPressed: () {
                        _update(_session.selectPrevious, haptic: false);
                        _centerOnSelected();
                      },
                      icon: const Icon(Icons.chevron_left_rounded, size: 30),
                    ),
                  Expanded(
                    child: InkWell(
                      onTap: isPoint ? null : _showVertexList,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  if (!isPoint)
                    IconButton(
                      tooltip: 'Next point',
                      onPressed: () {
                        _update(_session.selectNext, haptic: false);
                        _centerOnSelected();
                      },
                      icon: const Icon(Icons.chevron_right_rounded, size: 30),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: button.merge(FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor)),
                      onPressed: _session.canMove ? _moveHere : null,
                      icon: const Icon(Icons.open_with_rounded),
                      label: const Text('Move here'),
                    ),
                  ),
                  if (!isPoint) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: button,
                        onPressed: _session.canInsert ? _insert : null,
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Insert'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: button.merge(OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700)),
                        onPressed: _session.canDelete ? _delete : null,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points.map(_ll).toList();
    final MapOptions options = pts.isEmpty
        ? MapOptions(
            initialCenter: const LatLng(-2.5, 118),
            initialZoom: 5,
            maxZoom: 22,
            onTap: _onMapTap,
          )
        : pts.length == 1
            ? MapOptions(
                initialCenter: pts.first,
                initialZoom: 18,
                maxZoom: 22,
                onTap: _onMapTap,
              )
            : MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(pts),
                  padding: const EdgeInsets.all(60),
                  maxZoom: 19,
                ),
                maxZoom: 22,
                onTap: _onMapTap,
              );

    return PopScope(
      canPop: !_session.isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? 'Edit geometry'),
          actions: [
            IconButton(
              tooltip: 'Undo',
              onPressed: _session.canUndo ? _undo : null,
              icon: const Icon(Icons.undo_rounded),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'reset') _update(_session.reset);
                if (v == 'list') _showVertexList();
              },
              itemBuilder: (_) => [
                if (widget.type != GeometryType.point)
                  const PopupMenuItem(
                      value: 'list', child: Text('List of points')),
                PopupMenuItem(
                  value: 'reset',
                  enabled: _session.isDirty,
                  child: const Text('Reset to original'),
                ),
              ],
            ),
            TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Done',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ],
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: options,
              children: [
                if (widget.showBasemap)
                  if (_basemap != null)
                    ...buildBasemapLayers(
                      _basemap!,
                      overlay: _pdfOverlay.spec,
                      fallback: _osmLayer,
                    )
                  else
                    _osmLayer(),
                ..._geometryLayers(),
              ],
            ),
            // Crosshair: posisi tujuan "Move here" / "Insert".
            const IgnorePointer(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.add, size: 44, color: Colors.white),
                    Icon(Icons.add, size: 36, color: Colors.black87),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'geometry-editor-location',
                tooltip: 'Go to my location',
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryColor,
                onPressed: _goToMyLocation,
                child: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _toolbar(),
      ),
    );
  }

  TileLayer _osmLayer() => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: ApiConfig.bundleName,
      );
}
