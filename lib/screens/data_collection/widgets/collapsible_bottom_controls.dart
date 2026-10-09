import 'package:flutter/material.dart';
import '../../../models/project_model.dart';
import '../../../theme/app_theme.dart';
import '../data_collection_screen.dart' show CollectionMode;

/// Tinggi panel kontrol bawah — dipakai juga layar koleksi untuk menaruh
/// tombol peta di atasnya (satu sumber kebenaran).
class BottomControlsMetrics {
  /// Ruang minimal di bawah tombol bila HP tanpa bilah navigasi.
  static const double minBottomGap = 8.0;

  /// Tinggi isi (tanpa ruang bawah): pegangan 24 + baris tombol 52.
  static const double collapsed = 76.0;

  /// Tinggi isi saat diperluas: pegangan 24 + 4 + baris 52 (+ 12 + baris 52
  /// untuk Start/Stop & Pause saat tracking line/polygon). Dulu angkanya
  /// lebih besar dari isi sehingga tersisa ruang putih di bawah tombol.
  static double expanded(GeometryType type, CollectionMode mode) =>
      (type != GeometryType.point && mode == CollectionMode.tracking)
          ? 144.0 // Start/Stop + Pause/Resume, lalu Add/Undo/Clear
          : 80.0; // hanya Add/Undo/Clear

  /// Tinggi panel = isi + ruang bawah. Ruang bawah = bilah navigasi HP
  /// ([bottomInset]), minimal [minBottomGap] — tidak ditumpuk.
  static double height({
    required bool expanded,
    required GeometryType type,
    required CollectionMode mode,
    required double bottomInset,
  }) =>
      (expanded ? BottomControlsMetrics.expanded(type, mode) : collapsed) +
      (bottomInset > minBottomGap ? bottomInset : minBottomGap);
}

class CollapsibleBottomControls extends StatefulWidget {
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
  }) : super(key: key);

  @override
  State<CollapsibleBottomControls> createState() => _CollapsibleBottomControlsState();
}

class _CollapsibleBottomControlsState extends State<CollapsibleBottomControls> {
  double _dragPosition = 0.0;
  bool _isDragging = false;

  bool get _hasTrackingControls =>
      widget.geometryType != GeometryType.point &&
      widget.collectionMode == CollectionMode.tracking;

  bool get _canAddPoint =>
      !widget.isTracking && widget.collectionMode != CollectionMode.drawing;

  void _handleVerticalDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragPosition = 0.0;
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragPosition += details.delta.dy;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });

    // Threshold untuk menentukan apakah harus expand atau collapse
    const threshold = 50.0;

    if (_dragPosition.abs() > threshold) {
      // Swipe up (negative) = expand, Swipe down (positive) = collapse
      if (_dragPosition < 0 && !widget.isExpanded) {
        widget.onToggleExpanded();
      } else if (_dragPosition > 0 && widget.isExpanded) {
        widget.onToggleExpanded();
      }
    }

    setState(() {
      _dragPosition = 0.0;
    });
  }

  ButtonStyle _filled(Color color) => ElevatedButton.styleFrom(
        minimumSize: const Size(0, 52),
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey[300],
        disabledForegroundColor: Colors.grey[600],
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );

  /// Label tombol selalu satu baris (mengecil bila tak muat), supaya tinggi
  /// tombol tetap 52 dan panel pas dengan [BottomControlsMetrics].
  Widget _oneLine(Widget label) =>
      FittedBox(fit: BoxFit.scaleDown, child: label);

  Widget _trackingButton() => ElevatedButton.icon(
        onPressed: widget.onToggleTracking,
        icon: Icon(widget.isTracking ? Icons.stop : Icons.play_arrow, size: 24),
        label: _oneLine(Text(
          widget.isTracking ? 'Stop' : 'Start',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        )),
        style: _filled(widget.isTracking ? Colors.red : AppTheme.primaryColor),
      );

  Widget _pauseButton() => ElevatedButton.icon(
        onPressed: widget.onTogglePause,
        icon: Icon(widget.isPaused ? Icons.play_arrow : Icons.pause, size: 24),
        label: _oneLine(Text(
          widget.isPaused ? 'Resume' : 'Pause',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        )),
        style: _filled(widget.isPaused ? Colors.green : Colors.orange),
      );

  Widget _addPointButton() => ElevatedButton.icon(
        onPressed: _canAddPoint ? widget.onAddPoint : null,
        icon: const Icon(Icons.add_location, size: 24),
        label: _oneLine(const Text(
          'Add point',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        )),
        style: _filled(AppTheme.primaryColor),
      );

  /// Tampilan ringkas: aksi utama tetap satu ketukan (dulu hanya teks
  /// "Swipe up for controls").
  Widget _buildCompactRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
      child: Row(
        children: [
          if (_hasTrackingControls) ...[
            Expanded(child: _trackingButton()),
            if (widget.isTracking) ...[
              const SizedBox(width: 8),
              Expanded(child: _pauseButton()),
            ],
          ] else
            Expanded(child: _addPointButton()),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'More controls',
            iconSize: 30,
            onPressed: widget.onToggleExpanded,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ruang bawah = bilah navigasi HP (minimal 8), sama dengan SafeArea di
    // bawah — tinggi panel pas dengan isinya.
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    double heightFor(bool expanded) => BottomControlsMetrics.height(
          expanded: expanded,
          type: widget.geometryType,
          mode: widget.collectionMode,
          bottomInset: bottomPadding,
        );

    final double collapsedHeight = heightFor(false);
    final double expandedHeight = heightFor(true);

    final double targetHeight = widget.isExpanded ? expandedHeight : collapsedHeight;
    final double currentHeight = _isDragging
        ? (targetHeight - _dragPosition).clamp(collapsedHeight, expandedHeight)
        : targetHeight;

    return GestureDetector(
      onVerticalDragStart: _handleVerticalDragStart,
      onVerticalDragUpdate: _handleVerticalDragUpdate,
      onVerticalDragEnd: _handleVerticalDragEnd,
      child: AnimatedContainer(
        duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: currentHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: SafeArea(
          top: false,
          minimum:
              const EdgeInsets.only(bottom: BottomControlsMetrics.minBottomGap),
          child: SingleChildScrollView(
            // Saat drag, tinggi sementara bisa lebih kecil dari konten.
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag Handle
                GestureDetector(
                  onTap: widget.onToggleExpanded,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Container(
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),

                if (!widget.isExpanded)
                  _buildCompactRow()
                else
                  Padding(
                    // Tanpa padding bawah: ruang bawah dari SafeArea saja.
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tracking mode controls
                        if (_hasTrackingControls) ...[
                          Row(
                            children: [
                              Expanded(child: _trackingButton()),
                              // Pause/Resume button (only when tracking)
                              if (widget.isTracking) ...[
                                const SizedBox(width: 8),
                                Expanded(child: _pauseButton()),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Bottom row: Add Point, Undo, Clear
                        Row(
                          children: [
                            Expanded(
                              flex: 8,
                              child: ElevatedButton.icon(
                                onPressed:
                                    _canAddPoint ? widget.onAddPoint : null,
                                icon: const Icon(Icons.add_location, size: 22),
                                label: _oneLine(Text(
                                  widget.geometryType == GeometryType.point
                                      ? 'Add point (crosshair)'
                                      : 'Add point',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                )),
                                style: _filled(AppTheme.primaryColor),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Undo button (icon-only)
                            Expanded(
                              flex: 3,
                              child: Tooltip(
                                message: 'Undo last point',
                                child: OutlinedButton(
                                  onPressed: widget.collectedPoints.isEmpty
                                      ? null
                                      : widget.onUndoPoint,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 52),
                                    foregroundColor: AppTheme.primaryColor,
                                    side: BorderSide(
                                      color: widget.collectedPoints.isEmpty
                                          ? Colors.grey[300]!
                                          : AppTheme.primaryColor,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Icon(Icons.undo, size: 24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Clear button (icon-only) — minta konfirmasi &
                            // bisa di-Undo (lihat layar koleksi).
                            Expanded(
                              flex: 3,
                              child: Tooltip(
                                message: 'Clear all points',
                                child: OutlinedButton(
                                  onPressed: widget.collectedPoints.isEmpty
                                      ? null
                                      : widget.onClearPoints,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 52),
                                    foregroundColor: Colors.red,
                                    side: BorderSide(
                                      color: widget.collectedPoints.isEmpty
                                          ? Colors.grey[300]!
                                          : Colors.red,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Icon(Icons.delete_sweep_outlined,
                                      size: 24),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
