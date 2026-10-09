import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import '../../../models/project_model.dart';
import '../../../theme/app_theme.dart';
import '../data_collection_screen.dart' show CollectionMode;

/// Panel kontrol koleksi: kartu mengambang di atas bilah navigasi / home
/// indicator HP (di bawahnya peta, bukan pita putih). Tinggi mengikuti isi
/// (diukur, bukan angka tetap — padding tombol dari tema dulu membuat isi
/// terpotong) dan dilaporkan lewat [onHeightChanged] untuk tombol peta.
class CollapsibleBottomControls extends StatefulWidget {
  /// Key kartu putih (untuk test).
  static const cardKey = ValueKey<String>('collect-controls-card');

  /// Perkiraan tinggi sebelum ukuran pertama terlapor.
  static const double initialHeightEstimate = 150.0;

  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final GeometryType geometryType;
  final CollectionMode collectionMode;
  final bool isTracking;
  final bool isPaused;
  final List collectedPoints;
  final VoidCallback onToggleTracking;
  final VoidCallback onTogglePause;
  final VoidCallback onAddPoint;
  final VoidCallback onUndoPoint;
  final VoidCallback onClearPoints;

  /// Tinggi yang ditempati panel dari tepi bawah layar (kartu + jarak bawah).
  final ValueChanged<double>? onHeightChanged;

  const CollapsibleBottomControls({
    Key? key,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.geometryType,
    required this.collectionMode,
    required this.isTracking,
    required this.isPaused,
    required this.collectedPoints,
    required this.onToggleTracking,
    required this.onTogglePause,
    required this.onAddPoint,
    required this.onUndoPoint,
    required this.onClearPoints,
    this.onHeightChanged,
  }) : super(key: key);

  @override
  State<CollapsibleBottomControls> createState() => _CollapsibleBottomControlsState();
}

class _CollapsibleBottomControlsState extends State<CollapsibleBottomControls> {
  static const double _buttonHeight = 48;
  static const double _margin = 12;

  /// Geser dianggap disengaja bila lebih jauh dari ini, atau secepat
  /// [_flingVelocity] (geser cepat yang pendek dulu diabaikan).
  static const double _dragDistance = 24;
  static const double _flingVelocity = 300;

  double _dragDy = 0;

  bool get _hasTrackingControls =>
      widget.geometryType != GeometryType.point &&
      widget.collectionMode == CollectionMode.tracking;

  bool get _canAddPoint =>
      !widget.isTracking && widget.collectionMode != CollectionMode.drawing;

  void _onDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    final fling = v.abs() > _flingVelocity;
    final down = fling ? v > 0 : _dragDy > _dragDistance;
    final up = fling ? v < 0 : _dragDy < -_dragDistance;
    if ((down && widget.isExpanded) || (up && !widget.isExpanded)) {
      widget.onToggleExpanded();
    }
    _dragDy = 0;
  }

  ButtonStyle _filled(Color color) => ElevatedButton.styleFrom(
        minimumSize: const Size(0, _buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey[300],
        disabledForegroundColor: Colors.grey[600],
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  /// Label tombol selalu satu baris (mengecil bila tak muat).
  Widget _oneLine(String text, {FontWeight weight = FontWeight.bold}) =>
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, style: TextStyle(fontSize: 16, fontWeight: weight)),
      );

  Widget _trackingButton() => ElevatedButton.icon(
        onPressed: widget.onToggleTracking,
        icon: Icon(widget.isTracking ? Icons.stop : Icons.play_arrow, size: 24),
        label: _oneLine(widget.isTracking ? 'Stop' : 'Start'),
        style: _filled(widget.isTracking ? Colors.red : AppTheme.primaryColor),
      );

  Widget _pauseButton() => ElevatedButton.icon(
        onPressed: widget.onTogglePause,
        icon: Icon(widget.isPaused ? Icons.play_arrow : Icons.pause, size: 24),
        label: _oneLine(widget.isPaused ? 'Resume' : 'Pause'),
        style: _filled(widget.isPaused ? Colors.green : Colors.orange),
      );

  Widget _addPointButton() => Tooltip(
        message: widget.geometryType == GeometryType.point
            ? 'Add point at the crosshair'
            : 'Add point',
        child: ElevatedButton.icon(
          onPressed: _canAddPoint ? widget.onAddPoint : null,
          icon: const Icon(Icons.add_location, size: 22),
          label: _oneLine('Add point', weight: FontWeight.w600),
          style: _filled(AppTheme.primaryColor),
        ),
      );

  Widget _iconAction({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final enabled = widget.collectedPoints.isNotEmpty;
    return SizedBox(
      width: 56,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, _buttonHeight),
            padding: EdgeInsets.zero,
            foregroundColor: color,
            side: BorderSide(color: enabled ? color : Colors.grey[300]!),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: Icon(icon, size: 24),
        ),
      ),
    );
  }

  /// Undo & Clear (minta konfirmasi & bisa di-Undo, lihat layar koleksi).
  List<Widget> _editActions() => [
        const SizedBox(width: 8),
        _iconAction(
          tooltip: 'Undo last point',
          icon: Icons.undo,
          color: AppTheme.primaryColor,
          onPressed: widget.onUndoPoint,
        ),
        const SizedBox(width: 8),
        _iconAction(
          tooltip: 'Clear all points',
          icon: Icons.delete_sweep_outlined,
          color: Colors.red,
          onPressed: widget.onClearPoints,
        ),
      ];

  Widget _toggleButton() => SizedBox(
        width: 40,
        height: _buttonHeight,
        child: IconButton(
          tooltip: widget.isExpanded ? 'Hide controls' : 'Show controls',
          padding: EdgeInsets.zero,
          iconSize: 28,
          color: AppTheme.textSecondary,
          onPressed: widget.onToggleExpanded,
          icon: Icon(widget.isExpanded
              ? Icons.keyboard_arrow_down_rounded
              : Icons.keyboard_arrow_up_rounded),
        ),
      );

  /// Baris utama (selalu tampil): aksi utama + tombol sembunyikan/munculkan.
  Widget _mainRow() => Row(
        children: [
          if (_hasTrackingControls) ...[
            Expanded(child: _trackingButton()),
            if (widget.isTracking) ...[
              const SizedBox(width: 8),
              Expanded(child: _pauseButton()),
            ],
          ] else ...[
            Expanded(child: _addPointButton()),
            if (widget.isExpanded) ..._editActions(),
          ],
          const SizedBox(width: 4),
          _toggleButton(),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return _HeightReporter(
      onHeight: widget.onHeightChanged,
      child: Padding(
        // Jarak bawah = bilah navigasi HP (minimal 12); area ini tembus ke peta.
        padding: EdgeInsets.fromLTRB(
            _margin, 0, _margin, inset > _margin ? inset : _margin),
        child: GestureDetector(
          onVerticalDragStart: (_) => _dragDy = 0,
          onVerticalDragUpdate: (d) => _dragDy += d.delta.dy,
          onVerticalDragEnd: _onDragEnd,
          child: DecoratedBox(
            key: CollapsibleBottomControls.cardKey,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pegangan: ketuk untuk sembunyikan/munculkan.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onToggleExpanded,
                      child: SizedBox(
                        width: double.infinity,
                        height: 20,
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _mainRow(),
                    if (widget.isExpanded && _hasTrackingControls) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _addPointButton()),
                        ..._editActions(),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Melaporkan tinggi anaknya setiap kali berubah (setelah frame selesai).
class _HeightReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<double>? onHeight;

  const _HeightReporter({required this.onHeight, required super.child});

  @override
  _RenderHeightReporter createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
          BuildContext context, _RenderHeightReporter renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderHeightReporter extends RenderProxyBox {
  ValueChanged<double>? onHeight;
  double? _reported;

  _RenderHeightReporter(this.onHeight);

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight?.call(height);
    });
  }
}
