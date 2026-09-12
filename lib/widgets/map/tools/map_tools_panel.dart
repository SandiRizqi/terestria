import 'package:flutter/material.dart';

import '../../../models/settings/app_settings.dart';
import '../../../services/settings_service.dart';
import '../../../theme/app_theme.dart';
import '../map_tool_button.dart';
import 'map_tools_controller.dart';

/// Panel alat ukur peta: tombol launcher yang membuka daftar mode, kartu hasil
/// live, serta undo/clear/close. Gaya mengikuti [AppTheme]. Bind ke
/// [MapToolsController]; sertakan di Stack layar peta (host yang menempatkan
/// posisinya, mis. Positioned kanan-bawah).
class MapToolsPanel extends StatefulWidget {
  final MapToolsController controller;
  const MapToolsPanel({super.key, required this.controller});

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

  // ─── Kartu hasil live ─────────────────────────────────────────────────────
  Widget _resultCard(MapToolsController c) {
    final settings = SettingsService().settings;
    return Container(
      width: 200,
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium, vertical: 10),
      decoration: AppTheme.getCardDecoration,
      child: Row(
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
        ],
      ),
    );
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
