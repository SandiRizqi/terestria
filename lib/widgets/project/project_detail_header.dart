import 'package:flutter/material.dart';

import '../../services/data_view_mode_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/relative_time.dart';
import 'data_view_toggle.dart';

/// Potongan header detail project mengikuti template "Project detail · data"
/// (judul, statistik, banner sync, cari + filter, jumlah record). Warna hanya
/// dari [AppTheme].

String _plural(int n, String one, String many) => n == 1 ? '$n $one' : '$n $many';

const _cardRadius = 16.0;

/// Nama project besar + "Created by … · updated …".
class ProjectDetailTitle extends StatelessWidget {
  final String name;
  final String? createdBy;
  final DateTime updatedAt;

  /// Untuk test; bawaan jam sekarang.
  final DateTime? now;

  const ProjectDetailTitle({
    super.key,
    required this.name,
    required this.createdBy,
    required this.updatedAt,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final updated = relativeTime(updatedAt, now ?? DateTime.now());
    final who = createdBy?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          who == null || who.isEmpty
              ? 'Updated $updated'
              : 'Created by $who · updated $updated',
          style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

/// Kartu statistik ringkas: Type | Records | Fields.
class ProjectStatsRow extends StatelessWidget {
  final String type;
  final int records;
  final int fields;

  const ProjectStatsRow({
    super.key,
    required this.type,
    required this.records,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _cell('Type', type),
            VerticalDivider(width: 1, color: Colors.grey.shade200),
            _cell('Records', '$records'),
            VerticalDivider(width: 1, color: Colors.grey.shade200),
            _cell('Fields', '$fields'),
          ],
        ),
      ),
    );
  }

  Widget _cell(String label, String value) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
}

/// Banner antrean sync: record/foto yang belum ter-upload + tombol Sync
/// (project → record → foto sekaligus).
class SyncPendingBanner extends StatelessWidget {
  final int unsyncedCount;
  final int pendingPhotoCount;
  final bool projectSynced;
  final bool isOnline;
  final bool isSyncing;
  final VoidCallback onSync;

  const SyncPendingBanner({
    super.key,
    required this.unsyncedCount,
    required this.pendingPhotoCount,
    required this.projectSynced,
    required this.isOnline,
    required this.isSyncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final title = unsyncedCount == 0
        ? 'Project not on the server yet'
        : '${_plural(unsyncedCount, 'record', 'records')} not synced';
    final hint = !isOnline
        ? 'Offline — safe on this phone'
        : !projectSynced
            ? 'Sync uploads the project first'
            : 'Tap Sync to upload';
    final subtitle = [
      if (pendingPhotoCount > 0)
        '${_plural(pendingPhotoCount, 'photo', 'photos')} pending',
      hint,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: isOnline && !isSyncing ? onSync : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.textPrimary,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sync',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Kotak cari data + tombol filter dengan lencana jumlah filter aktif.
class DataSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final int activeFilterCount;
  final VoidCallback onOpenFilters;

  const DataSearchBar({
    super.key,
    required this.controller,
    required this.activeFilterCount,
    required this.onOpenFilters,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search data...',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.textSecondary),
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: controller.clear,
                      ),
                filled: true,
                fillColor: AppTheme.cardBackground,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide:
                      const BorderSide(color: AppTheme.primaryGreen, width: 2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onOpenFilters,
                child: const Tooltip(
                  message: 'Filters',
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: Icon(Icons.tune_rounded, color: Colors.white),
                  ),
                ),
              ),
            ),
            if (activeFilterCount > 0)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  constraints: const BoxConstraints(minWidth: 22),
                  decoration: const BoxDecoration(
                    color: AppTheme.warningColor,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$activeFilterCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// "248 records" / "12 of 248 records" + Clear filters + tombol grid/list.
class RecordsHeaderRow extends StatelessWidget {
  final int visibleCount;
  final int totalCount;
  final bool hasActiveFilters;
  final VoidCallback onClearFilters;
  final DataViewMode viewMode;
  final ValueChanged<DataViewMode> onViewModeChanged;

  const RecordsHeaderRow({
    super.key,
    required this.visibleCount,
    required this.totalCount,
    required this.hasActiveFilters,
    required this.onClearFilters,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            hasActiveFilters
                ? '$visibleCount of ${_plural(totalCount, 'record', 'records')}'
                : _plural(totalCount, 'record', 'records'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        if (hasActiveFilters)
          TextButton(
            onPressed: onClearFilters,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.errorColor,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Clear filters',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        const Spacer(),
        DataViewToggle(mode: viewMode, onChanged: onViewModeChanged),
      ],
    );
  }
}
