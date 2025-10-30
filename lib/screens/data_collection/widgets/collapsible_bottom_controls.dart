import 'package:flutter/material.dart';
import '../../../models/project_model.dart';
import '../../../theme/app_theme.dart';
import '../data_collection_screen.dart' show CollectionMode;

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

  @override
  Widget build(BuildContext context) {
    final double targetHeight = widget.isExpanded ? 180.0 : 60.0;
    final double currentHeight = _isDragging 
        ? (targetHeight - _dragPosition).clamp(60.0, 180.0)
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            GestureDetector(
              onTap: widget.onToggleExpanded,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
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

              if (!widget.isExpanded)
              // Compact view - hanya teks info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.swipe_up,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Swipe up for controls',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              )
            else
              // Expanded view - semua kontrol
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingMedium),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tracking mode controls
                        if (widget.geometryType != GeometryType.point &&
                            widget.collectionMode == CollectionMode.tracking) ...[
                          Row(
                            children: [
                              // Start/Finish button
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  onPressed: widget.onToggleTracking,
                                  icon: Icon(
                                    widget.isTracking ? Icons.stop : Icons.play_arrow,
                                    size: 20,
                                  ),
                                  label: Text(
                                    widget.isTracking ? 'Finish' : 'Start',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    backgroundColor: widget.isTracking
                                        ? Colors.red
                                        : AppTheme.primaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),

                              // Pause/Resume button (only when tracking)
                              if (widget.isTracking) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton.icon(
                                    onPressed: widget.onTogglePause,
                                    icon: Icon(
                                      widget.isPaused ? Icons.play_arrow : Icons.pause,
                                      size: 20,
                                    ),
                                    label: Text(
                                      widget.isPaused ? 'Resume' : 'Pause',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      backgroundColor:
                                          widget.isPaused ? Colors.green : Colors.orange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Bottom row: Add Point, Undo, Clear
                        Row(
                          children: [
                            // Add Point button
                            Expanded(
                              flex: 3,
                              child: ElevatedButton.icon(
                                onPressed: (widget.isTracking ||
                                        widget.collectionMode == CollectionMode.drawing)
                                    ? null
                                    : widget.onAddPoint,
                                icon: const Icon(Icons.add_location, size: 20),
                                label: Text(
                                  widget.geometryType == GeometryType.point
                                      ? 'Add Point (Center)'
                                      : 'Add Point',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  backgroundColor: AppTheme.primaryColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey[300],
                                  disabledForegroundColor: Colors.grey[500],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Undo button
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    widget.collectedPoints.isEmpty ? null : widget.onUndoPoint,
                                icon: const Icon(Icons.undo, size: 18),
                                label: const Text('Undo',
                                    style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  foregroundColor: AppTheme.primaryColor,
                                  side: BorderSide(
                                    color: widget.collectedPoints.isEmpty
                                        ? Colors.grey[300]!
                                        : AppTheme.primaryColor,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Clear button
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    widget.collectedPoints.isEmpty ? null : widget.onClearPoints,
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: const Text('Clear',
                                    style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  foregroundColor: Colors.red,
                                  side: BorderSide(
                                    color: widget.collectedPoints.isEmpty
                                        ? Colors.grey[300]!
                                        : Colors.red,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
