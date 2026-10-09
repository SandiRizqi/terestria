import 'package:flutter/material.dart';

import '../../../models/settings/app_settings.dart';
import '../../../services/settings_service.dart';
import '../../../theme/app_theme.dart';
import 'package:latlong2/latlong.dart';

import '../map_tool_button.dart';
import 'coordinate_dialog.dart';
import 'coordinate_input.dart';
import 'map_tools_controller.dart';

/// Panel alat ukur peta: tombol launcher yang membuka daftar mode, kartu hasil
/// live, serta undo/clear/close. Gaya mengikuti [AppTheme]. Bind ke
/// [MapToolsController]; sertakan di Stack layar peta (host yang menempatkan
/// posisinya, mis. Positioned kanan-bawah).
class MapToolsPanel extends StatefulWidget {
  final MapToolsController controller;

  /// Dipanggil setelah titik diketik/diedit, agar host menggeser peta ke sana.
  final ValueChanged<LatLng>? onFocusPoint;

  const MapToolsPanel(
      {super.key, required this.controller, this.onFocusPoint});

  @override
  State<MapToolsPanel> createState() => _MapToolsPanelState();
}

class _MapToolsPanelState extends State<MapToolsPanel> {
  bool _open = false;

  static const _entries = <(MapToolMode, String, IconData)>[
    (MapToolMode.distance, 'Distance', Icons.straighten),
    (MapToolMode.area, 'Area', Icons.crop_square),
    (MapToolMode.bearing, 'Bearing', Icons.explore_outlined),
    (MapToolMode.coordinate, 'Coordinate', Icons.my_location),
    (MapToolMode.radius, 'Radius', Icons.radio_button_unchecked),
  ];

  IconData _iconFor(MapToolMode m) =>
      _entries.firstWhere((e) => e.$1 == m, orElse: () => _entries.first).$3;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final AppSettings settings = SettingsService().settings;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (c.isActive) _resultCard(c),
            if (_open) _modeMenu(c),
            _controlsRow(c),
          ],
        );
      },
    );
  }

  // ─── Kartu hasil live + titik yang bisa diketik/diedit ─────────────────────
  Widget _resultCard(MapToolsController c) {
    final settings = SettingsService().settings;
    final isCoordinate = c.mode == MapToolMode.coordinate;
    // Mode koordinat: hasilnya sendiri adalah koordinat titik → ketuk = edit.
    final editableResult = isCoordinate && c.points.isNotEmpty;
    final resultRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_iconFor(c.mode), size: 16, color: AppTheme.primaryGreen),
        const SizedBox(width: AppTheme.spacingSmall),
        Expanded(
          child: Text(
            c.resultText(settings),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        if (editableResult)
          const Icon(Icons.edit_outlined,
              size: 16, color: AppTheme.textSecondary),
      ],
    );
    return Container(
      width: 240,
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingMedium, 10, AppTheme.spacingSmall, 4),
      decoration: AppTheme.getCardDecoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editableResult)
            InkWell(
              key: const Key('mapToolsEditCoordinate'),
              onTap: () => _editPoint(c, 0),
              child: resultRow,
            )
          else
            resultRow,
          if (!isCoordinate && c.points.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 132),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: c.points.length,
                itemBuilder: (context, i) => _pointRow(c, i),
              ),
            ),
          ],
          TextButton.icon(
            key: const Key('mapToolsAddCoordinate'),
            onPressed: () => _addPoint(c),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryGreen,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: Text(
              isCoordinate ? 'Enter coordinate' : 'Add by coordinate',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Satu titik: nomor + koordinat; ketuk untuk mengetik ulang koordinatnya.
  Widget _pointRow(MapToolsController c, int i) {
    return InkWell(
      key: Key('mapToolsPoint_$i'),
      onTap: () => _editPoint(c, i),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacingSmall),
            Expanded(
              child: Text(
                formatCoordinate(c.points[i]),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Icon(Icons.edit_outlined,
                size: 14, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _editPoint(MapToolsController c, int index) async {
    final p = await showCoordinateDialog(
      context,
      title: c.mode == MapToolMode.coordinate
          ? 'Edit coordinate'
          : 'Edit point ${index + 1}',
      initial: c.points[index],
    );
    if (p == null || !mounted) return;
    c.updatePoint(index, p);
    widget.onFocusPoint?.call(p);
  }

  Future<void> _addPoint(MapToolsController c) async {
    final p = await showCoordinateDialog(
      context,
      title: c.mode == MapToolMode.coordinate ? 'Enter coordinate' : 'Add point',
      initial: c.lastPoint,
    );
    if (p == null || !mounted) return;
    c.addPoint(p);
    widget.onFocusPoint?.call(p);
  }

  // ─── Menu pilih mode ──────────────────────────────────────────────────────
  Widget _modeMenu(MapToolsController c) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      decoration: AppTheme.getCardDecoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _entries.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, indent: 52, endIndent: 12),
              _modeTile(c, _entries[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modeTile(MapToolsController c, (MapToolMode, String, IconData) e) {
    final active = c.mode == e.$1;
    final color = active ? AppTheme.primaryGreen : AppTheme.textSecondary;
    return Material(
      color: active ? AppTheme.primaryGreen.withValues(alpha: 0.10) : Colors.white,
      child: InkWell(
        onTap: () {
          c.setMode(e.$1);
          setState(() => _open = false);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMedium, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(e.$3, size: 20, color: color),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
              Expanded(
                child: Text(
                  e.$2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? AppTheme.primaryGreen : AppTheme.textPrimary,
                  ),
                ),
              ),
              if (active)
                const Icon(Icons.check_rounded,
                    size: 18, color: AppTheme.primaryGreen),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Baris kontrol (undo/clear/close + launcher) ─────────────────────────
  Widget _controlsRow(MapToolsController c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.isActive) ...[
            _miniBtn(
                key: const Key('mapToolsUndo'),
                icon: Icons.undo_rounded,
                tooltip: 'Undo',
                onTap: c.undo),
            const SizedBox(width: AppTheme.spacingSmall),
            _miniBtn(
                key: const Key('mapToolsClear'),
                icon: Icons.delete_outline_rounded,
                tooltip: 'Clear',
                onTap: c.clear),
            const SizedBox(width: AppTheme.spacingSmall),
            _miniBtn(
                key: const Key('mapToolsClose'),
                icon: Icons.close_rounded,
                tooltip: 'Close tool',
                onTap: () {
                  c.setMode(MapToolMode.none);
                  setState(() => _open = false);
                }),
            const SizedBox(width: AppTheme.spacingSmall),
          ],
          _launcher(c),
        ],
      );

  Widget _launcher(MapToolsController c) => MapToolButton(
        key: const Key('mapToolsLauncher'),
        tooltip: 'Measure',
        icon: _open ? Icons.close_rounded : Icons.straighten,
        active: c.isActive,
        onPressed: () => setState(() => _open = !_open),
      );

  Widget _miniBtn({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Material(
        key: key,
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Tooltip(
              message: tooltip,
              child: Icon(icon, size: 18, color: AppTheme.textSecondary),
            ),
          ),
        ),
      );
}
