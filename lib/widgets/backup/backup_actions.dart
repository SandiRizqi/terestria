import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/app_reset/local_backup_service.dart';
import '../../services/auth_service.dart';
import '../../services/device_health_service.dart' show formatBytes;
import '../../utils/app_logger.dart';
import '../../utils/share_origin.dart';
import '../../utils/ui_feedback.dart';

/// Membuka share sheet untuk berkas (default: `Share.shareXFiles`).
typedef ShareFilesFn = Future<ShareResult> Function(
  List<XFile> files, {
  String? subject,
  String? text,
  Rect? sharePositionOrigin,
});

Future<LocalBackupResult> _defaultCreateBackup() async {
  final user = await AuthService().getUser();
  return LocalBackupService().create(username: user?.username);
}

/// Buat berkas cadangan (ZIP) semua data di HP lalu buka share sheet (Drive,
/// Files, email, …). Mengembalikan true bila cadangan dibuat & dibagikan —
/// FALSE bila user menutup share sheet tanpa menyimpan (berkasnya di folder
/// Temp dan ikut terhapus saat logout, jadi jangan dianggap aman).
///
/// Dipakai dialog logout (logout menghapus semua data) dan Settings.
/// [createBackup] & [share] dapat disuntik untuk pengujian.
Future<bool> createAndShareBackup(
  BuildContext context, {
  Future<LocalBackupResult> Function()? createBackup,
  ShareFilesFn? share,
}) async {
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
    backup = await (createBackup ?? _defaultCreateBackup)();
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

  final ShareResult shared;
  try {
    shared = await (share ?? Share.shareXFiles)(
      [XFile(backup.file.path, mimeType: 'application/zip')],
      subject: 'Terestria backup',
      text: 'Terestria backup: ${backup.records} records '
          '(${backup.unsyncedRecords} unsynced), ${backup.photos} photos.',
      sharePositionOrigin: origin,
    );
    logInfo('Backup share sheet closed (${shared.status.name}): '
        '${backup.file.path}', tag: 'BACKUP');
  } catch (e, st) {
    if (context.mounted) {
      showErrorFeedback(context, 'Could not open the share sheet',
          error: e, stack: st, tag: 'BACKUP');
    }
    return false;
  }
  if (shared.status == ShareResultStatus.dismissed) {
    // iOS melapor share sheet ditutup tanpa aksi → berkas belum disimpan di
    // mana pun (dan akan terhapus saat logout).
    if (context.mounted) {
      showInfoFeedback(
        context,
        'The backup was not saved — the share sheet was closed. Tap '
        '"Save a backup file" again and choose where to keep it.',
        warning: true,
        duration: const Duration(seconds: 8),
      );
    }
    return false;
  }
  if (!context.mounted) return true;
  final missing = backup.missingPhotos.length;
  final String message;
  if (missing > 0) {
    message = 'Backup ready, but $missing photo file(s) were already missing '
        'on this phone.';
  } else if (shared.status == ShareResultStatus.success) {
    message = 'Backup shared (${formatBytes(backup.bytes)}).';
  } else {
    // Android tak melaporkan pilihan user.
    message = 'Backup ready (${formatBytes(backup.bytes)}). Make sure it was '
        'saved somewhere safe.';
  }
  showInfoFeedback(
    context,
    message,
    success: missing == 0,
    warning: missing > 0,
    duration: const Duration(seconds: 6),
  );
  return true;
}
