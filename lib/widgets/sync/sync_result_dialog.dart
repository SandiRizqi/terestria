import 'package:flutter/material.dart';

import '../../services/sync_service.dart';
import '../../utils/ui_feedback.dart';

/// Tampilkan hasil "sync semua" (Beranda, sebelum logout, Readiness):
/// - semua terkirim → snackbar sukses;
/// - sesi habis / server tak terjangkau → snackbar penjelasan;
/// - ada yang gagal → dialog berisi ALASANNYA (mis. project nonaktif), bukan
///   sekadar "Data: 3/5 synced".
Future<void> showFullSyncResult(
  BuildContext context,
  FullSyncResult result, {
  VoidCallback? onRetry,
}) async {
  if (result.abortedDueToAuth) {
    showInfoFeedback(context, 'Your session expired — sign in again, then sync.',
        warning: true, duration: const Duration(seconds: 6));
    return;
  }
  if (result.abortedDueToConnection) {
    showInfoFeedback(
        context,
        'The server could not be reached. Your data is safe on this phone — '
        'try again later.',
        warning: true,
        duration: const Duration(seconds: 6));
    return;
  }
  if (!result.hasErrors) {
    showInfoFeedback(context, result.summary, success: true);
    return;
  }
  final uploaded = result.geoDataSuccess;
  await showSyncProblemsDialog(
    context,
    title: uploaded > 0 ? 'Some records were not uploaded' : 'Nothing was uploaded',
    summary: result.geoDataTotal > 0
        ? '$uploaded of ${result.geoDataTotal} records uploaded. The rest stay '
            'safely on this phone.'
        : 'Nothing was uploaded. Your data stays safely on this phone.',
    errors: result.errors,
    onRetry: onRetry,
  );
}

/// Dialog alasan gagal sync (dikelompokkan, maks 5 + "…and N more").
Future<void> showSyncProblemsDialog(
  BuildContext context, {
  required String title,
  required String summary,
  required List<String> errors,
  VoidCallback? onRetry,
}) {
  final grouped = SyncService.groupErrors(errors);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 32),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary),
            if (grouped.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Reasons:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final e in grouped.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $e', style: const TextStyle(fontSize: 13)),
                ),
              if (grouped.length > 5)
                Text('…and ${grouped.length - 5} more',
                    style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        if (onRetry != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onRetry();
            },
            child: const Text('Retry'),
          ),
      ],
    ),
  );
}
