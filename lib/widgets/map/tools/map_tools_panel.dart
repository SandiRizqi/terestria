import 'package:flutter/material.dart';

import '../../../models/settings/app_settings.dart';
import '../../../services/settings_service.dart';
import 'map_tools_controller.dart';

/// Panel alat ukur peta: tombol launcher yang membuka daftar mode, kartu hasil
/// live, serta undo/clear/close. Bind ke [MapToolsController]; sertakan di Stack
/// layar peta (host yang menempatkan posisinya, mis. Positioned kanan-bawah).
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
    (MapToolMode.bearing, 'Bearing', Icons.explore),
    (MapToolMode.coordinate, 'Coordinate', Icons.my_location),
    (MapToolMode.radius, 'Radius', Icons.radio_button_unchecked),
  ];

  static const Color _accent = Color(0xFFFF6D00);

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
            if (c.isActive) _resultCard(c.resultText(settings)),
            if (_open) _modeMenu(c),
            _controlsRow(c),
          ],
        );
      },
    );
  }

  Widget _resultCard(String text) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _modeMenu(MapToolsController c) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in _entries)
              InkWell(
                onTap: () {
                  c.setMode(e.$1);
                  setState(() => _open = false);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(e.$3,
                          size: 18,
                          color: c.mode == e.$1 ? _accent : Colors.black54),
                      const SizedBox(width: 10),
                      Text(e.$2,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: c.mode == e.$1
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color:
                                  c.mode == e.$1 ? _accent : Colors.black87)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _controlsRow(MapToolsController c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.isActive) ...[
            _miniBtn(
                key: const Key('mapToolsUndo'),
                icon: Icons.undo,
                tooltip: 'Undo',
                onTap: c.undo),
            const SizedBox(width: 6),
            _miniBtn(
                key: const Key('mapToolsClear'),
                icon: Icons.delete_outline,
                tooltip: 'Clear',
                onTap: c.clear),
            const SizedBox(width: 6),
            _miniBtn(
                key: const Key('mapToolsClose'),
                icon: Icons.close,
                tooltip: 'Close tool',
                onTap: () {
                  c.setMode(MapToolMode.none);
                  setState(() => _open = false);
                }),
            const SizedBox(width: 6),
          ],
          FloatingActionButton.small(
            key: const Key('mapToolsLauncher'),
            heroTag: 'mapToolsLauncher',
            backgroundColor: c.isActive ? _accent : Colors.white,
            foregroundColor: c.isActive ? Colors.white : Colors.black87,
            onPressed: () => setState(() => _open = !_open),
            child: const Icon(Icons.straighten),
          ),
        ],
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
            padding: const EdgeInsets.all(8),
            child: Tooltip(
                message: tooltip,
                child: Icon(icon, size: 18, color: Colors.black87)),
          ),
        ),
      );
}
