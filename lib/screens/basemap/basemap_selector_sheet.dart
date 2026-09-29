import 'package:flutter/material.dart';
import '../../models/basemap_model.dart';
import '../../services/basemap_service.dart';
import '../../theme/app_theme.dart';
import 'basemap_management_screen.dart';

/// Bottom sheet untuk memilih basemap aktif.
/// Digunakan di DataCollectionScreen dan NavigationScreen.
class BasemapSelectorSheet extends StatefulWidget {
  final Basemap? currentBasemap;
  final ValueChanged<Basemap> onBasemapSelected;

  const BasemapSelectorSheet({
    super.key,
    required this.currentBasemap,
    required this.onBasemapSelected,
  });

  @override
  State<BasemapSelectorSheet> createState() => _BasemapSelectorSheetState();
}

class _BasemapSelectorSheetState extends State<BasemapSelectorSheet> {
  final _basemapService = BasemapService();
  List<Basemap> _basemaps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBasemaps();
  }

  Future<void> _loadBasemaps() async {
    final basemaps = await _basemapService.getBasemaps();
    if (mounted) {
      setState(() {
        _basemaps = basemaps;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Choose basemap',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.settings_rounded, size: 16),
                  label: const Text('Manage'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryGreen,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BasemapManagementScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const Divider(height: 12),

            // ── List ────────────────────────────────────────────────────────
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_basemaps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No basemaps yet.\nAdd one with the "Manage" button.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ),
              )
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
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryGreen.withValues(alpha: 0.12)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.map_rounded,
                          size: 18,
                          color: isSelected
                              ? AppTheme.primaryGreen
                              : Colors.grey.shade500,
                        ),
                      ),
                      title: Text(
                        basemap.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? AppTheme.primaryGreen
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        basemap.type == BasemapType.builtin
                            ? 'Built-in'
                            : basemap.type == BasemapType.pdf
                                ? 'PDF'
                                : 'Custom TMS',
                        style:
                            const TextStyle(fontSize: 11),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppTheme.primaryGreen, size: 20)
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
