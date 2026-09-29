import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/app_reset/local_backup_service.dart';
import '../../services/auth_service.dart';
import '../../services/device_health_service.dart' show formatBytes;
import '../../utils/app_logger.dart';
import '../../utils/share_origin.dart';
import '../../utils/ui_feedback.dart';

/// Buat berkas cadangan (ZIP) semua data di HP lalu buka share sheet (Drive,
/// Files, email, …). Mengembalikan true bila cadangan dibuat & dibagikan.
///
/// Dipakai dialog logout (logout menghapus semua data) dan Settings.
Future<bool> createAndShareBackup(BuildContext context) async {
  // Rect share sheet dihitung SEBELUM await (context bisa sudah tak terpasang).
  final origin = shareOriginFor(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Expanded(child: Text('Creating backup file…')),
        ]),
      ),
    ),
  );

  LocalBackupResult? backup;
  Object? error;
  StackTrace? stack;
  try {
    final user = await AuthService().getUser();
    backup = await LocalBackupService().create(username: user?.username);
  } catch (e, st) {
    error = e;
    stack = st;
  }
  if (!context.mounted) return false;
  Navigator.of(context, rootNavigator: true).pop();
  if (backup == null) {
    showErrorFeedback(context, 'Could not create the backup file',
        error: error, stack: stack, tag: 'BACKUP');
    return false;
  }

  try {
    await Share.shareXFiles(
      [XFile(backup.file.path, mimeType: 'application/zip')],
      subject: 'Terestria backup',
      text: 'Terestria backup: ${backup.records} records '
          '(${backup.unsyncedRecords} unsynced), ${backup.photos} photos.',
      sharePositionOrigin: origin,
    );
    logInfo('Backup shared: ${backup.file.path}', tag: 'BACKUP');
  } catch (e, st) {
    if (context.mounted) {
      showErrorFeedback(context, 'Could not open the share sheet',
          error: e, stack: st, tag: 'BACKUP');
    }
    return false;
  }
  if (!context.mounted) return true;
  showInfoFeedback(
    context,
    backup.missingPhotos.isEmpty
        ? 'Backup ready (${formatBytes(backup.bytes)}). Make sure it was '
            'saved somewhere safe.'
        : 'Backup ready, but ${backup.missingPhotos.length} photo file(s) '
            'were already missing on this phone.',
    success: backup.missingPhotos.isEmpty,
    warning: backup.missingPhotos.isNotEmpty,
    duration: const Duration(seconds: 6),
  );
  return true;
}
