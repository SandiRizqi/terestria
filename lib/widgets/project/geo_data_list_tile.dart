import 'package:flutter/material.dart';

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../../models/settings/app_settings.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/record_summary.dart';
import '../../utils/record_title.dart';

/// Satu baris tampilan list data project: ikon geometri, judul, ringkasan
/// (isian kedua · luas/panjang · pengumpul, waktu), titik status sync, dan
/// menu edit/hapus — aksi yang sama dengan tile grid (`GeoDataListItem`).
class GeoDataListTile extends StatelessWidget {
  final GeoData geoData;
  final Project project;
  final String? currentUsername;

  /// Di mode pilih: mencentang/melepas record (bukan membuka detail).
  final VoidCallback onTap;

  /// Tekan lama: masuk mode pilih.
  final VoidCallback? onLongPress;

  /// Mode pilih: checkbox menggantikan ikon geometri, menu ⋮ disembunyikan.
  final bool selectionMode;
  final bool selected;

  /// Null bila user tidak boleh mengedit/menghapus record ini.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Untuk test; bawaan jam sekarang dan Settings aplikasi.
  final DateTime? now;
  final AppSettings? settings;

  const GeoDataListTile({
    super.key,
    required this.geoData,
    required this.project,
    required this.currentUsername,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onEdit,
    this.onDelete,
    this.now,
    this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _geometryStyle(project.geometryType);
    final syncError = geoData.isSynced ? null : geoData.lastSyncError;
    final subtitle = recordSubtitle(
      geoData,
      project,
      currentUsername: currentUsername,
      now: now ?? DateTime.now(),
      settings: settings ?? SettingsService().settings,
    );

    return Material(
      color: selectionMode && selected
          ? AppTheme.primaryGreen.withValues(alpha: 0.06)
          : AppTheme.cardBackground,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: selectionMode
                    ? Center(
                        child: Checkbox(
                          value: selected,
                          activeColor: AppTheme.primaryGreen,
                          onChanged: (_) => onTap(),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(
                              AppTheme.borderRadiusMedium),
                        ),
                        child: Icon(icon, size: 22, color: color),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recordTitle(geoData, project),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (syncError != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        syncError,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.errorColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SyncDot(synced: geoData.isSynced, failed: syncError != null),
              if (!selectionMode && (onEdit != null || onDelete != null))
                _actionsMenu()
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionsMenu() => PopupMenuButton<String>(
        tooltip: 'Record actions',
        icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        ),
        onSelected: (value) {
          if (value == 'edit') onEdit?.call();
          if (value == 'delete') onDelete?.call();
        },
        itemBuilder: (context) => [
          if (onEdit != null)
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_rounded, color: AppTheme.primaryColor),
                title: Text('Edit'),
              ),
            ),
          if (onDelete != null)
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_rounded, color: AppTheme.errorColor),
                title: Text('Delete'),
              ),
            ),
        ],
      );

  static (IconData, Color) _geometryStyle(GeometryType type) {
    switch (type) {
      case GeometryType.point:
        return (Icons.location_on, AppTheme.pointColor);
      case GeometryType.line:
        return (Icons.timeline, AppTheme.lineColor);
      case GeometryType.polygon:
        return (Icons.pentagon_outlined, AppTheme.polygonColor);
    }
  }
}

/// Titik status sync: hijau tersinkron, kuning belum di-upload, merah gagal.
class _SyncDot extends StatelessWidget {
  final bool synced;
  final bool failed;

  const _SyncDot({required this.synced, required this.failed});

  @override
  Widget build(BuildContext context) {
    final (color, label) = synced
        ? (AppTheme.successColor, 'Synced')
        : failed
            ? (AppTheme.errorColor, 'Upload failed')
            : (AppTheme.warningColor, 'Not uploaded yet');
    return Semantics(
      container: true,
      label: label,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
