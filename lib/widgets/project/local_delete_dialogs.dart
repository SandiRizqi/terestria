import 'package:flutter/material.dart';

import '../../models/geo_data_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/local_delete.dart';

/// Dialog peringatan sebelum menghapus data project dari HP. Penghapusan
/// hanya di HP: record yang sudah di server bisa di-Pull lagi, record yang
/// belum di-upload hilang permanen.

String _recordsText(int n) => n == 1 ? '1 record' : '$n records';

const _serverNote = 'Nothing is deleted on the server.';

/// Hapus record terpilih: true bila user menekan Delete.
Future<bool> confirmDeleteSelected(
    BuildContext context, List<GeoData> records) async {
  final c = countLocalDelete(records);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.delete_outline_rounded,
          color: AppTheme.errorColor, size: 32),
      title: Text('Delete ${_recordsText(c.total)} from this phone?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.onServer > 0)
            _Line(
              icon: Icons.cloud_done_outlined,
              text: '${c.onServer} already on the server stay there. '
                  'You can pull them again any time.',
            ),
          if (c.notUploaded > 0)
            _Line(
              icon: Icons.warning_amber_rounded,
              text: '${c.notUploaded} not uploaded yet will be lost '
                  'permanently. Sync first to keep them.',
              danger: true,
            ),
          const SizedBox(height: 4),
          const Text(_serverNote,
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Kosongkan data lokal project: id record yang dihapus, atau null bila
/// dibatalkan. Record belum di-upload hanya ikut bila user mencentangnya.
Future<List<String>?> confirmClearLocalData(
    BuildContext context, List<GeoData> records) {
  final c = countLocalDelete(records);
  var includeNotUploaded = false;
  return showDialog<List<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final ids =
            clearLocalIds(records, includeNotUploaded: includeNotUploaded);
        return AlertDialog(
          scrollable: true,
          icon: const Icon(Icons.cleaning_services_outlined,
              color: AppTheme.errorColor, size: 32),
          title: const Text('Clear local data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Removes this project's records from this phone only. "
                '$_serverNote',
                style: TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              if (c.onServer > 0)
                _Line(
                  icon: Icons.cloud_done_outlined,
                  text: '${_recordsText(c.onServer)} already on the server '
                      'will be removed. Pull them again any time.',
                ),
              if (c.notUploaded > 0)
                CheckboxListTile(
                  value: includeNotUploaded,
                  onChanged: (v) =>
                      setState(() => includeNotUploaded = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.errorColor,
                  title: Text(
                    'Also delete ${c.notUploaded} not uploaded yet',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'They will be lost permanently. Sync first to keep them.',
                    style: TextStyle(fontSize: 12, color: AppTheme.errorColor),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
              onPressed: ids.isEmpty ? null : () => Navigator.pop(context, ids),
              child: Text('Delete ${ids.length}'),
            ),
          ],
        );
      },
    ),
  );
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool danger;

  const _Line({required this.icon, required this.text, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.errorColor : AppTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                color: danger ? AppTheme.errorColor : AppTheme.textPrimary,
                fontWeight: danger ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
