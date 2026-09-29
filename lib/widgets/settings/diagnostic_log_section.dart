import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/background/background_tracking_service.dart';
import '../../services/logging/diagnostic_mode.dart';
import '../../services/logging/log_exporter.dart';
import '../../services/logging/log_setup.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/share_origin.dart';

// ─── Helper tampilan (murni, teruji) ─────────────────────────────────────────

String diagnosticStatusLabel(DateTime? until, DateTime now) {
  if (!DiagnosticMode.isActive(until, now)) return 'Mati';
  final left = until!.difference(now);
  return left.inHours >= 1
      ? 'Aktif · ${left.inHours} jam lagi'
      : 'Aktif · ${left.inMinutes} mnt lagi';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class LogStats {
  final int files;
  final int bytes;
  const LogStats({required this.files, required this.bytes});
}

/// Aksi section (disuntik agar bisa diuji tanpa berkas/plugin).
abstract class DiagnosticLogActions {
  Future<DateTime?> loadUntil();
  Future<DateTime> enable();
  Future<void> disable();
  Future<LogStats> stats();
  Future<void> clear();
  Future<void> share(BuildContext context);
}

/// Implementasi nyata: SharedPreferences + folder `<documents>/logs`.
class DefaultDiagnosticLogActions implements DiagnosticLogActions {
  const DefaultDiagnosticLogActions();

  static Future<List<File>> _logFiles() async {
    final dir = await logsDirectory();
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList();
  }

  @override
  Future<DateTime?> loadUntil() => DiagnosticMode.load();

  @override
  Future<DateTime> enable() async {
    final until = await DiagnosticMode.enable();
    _apply(until);
    logInfo('Mode Diagnostik AKTIF sampai $until', tag: 'LOG');
    return until;
  }

  @override
  Future<void> disable() async {
    await DiagnosticMode.disable();
    _apply(null);
    logInfo('Mode Diagnostik dimatikan', tag: 'LOG');
  }

  /// Berlaku langsung di isolate app & isolate background.
  void _apply(DateTime? until) {
    AppLogger.setDiagnosticUntil(until);
    BackgroundTrackingService().setDiagnosticUntil(until);
  }

  @override
  Future<LogStats> stats() async {
    await AppLogger.flush();
    final files = await _logFiles();
    var bytes = 0;
    for (final f in files) {
      bytes += await f.length();
    }
    return LogStats(files: files.length, bytes: bytes);
  }

  @override
  Future<void> clear() async {
    await AppLogger.flush();
    for (final f in await _logFiles()) {
      await f.delete();
    }
    logInfo('Log dihapus oleh user', tag: 'LOG');
  }

  /// Zip: log app+bg, 3 CSV GPS terbaru, info perangkat, snapshot tracking.
  /// Rect asal share sheet diambil dari [context] (baris yang ditekan)
  /// sebelum proses async dimulai.
  @override
  Future<void> share(BuildContext context) =>
      exportAndShareLogs(sharePositionOrigin: shareOriginFor(context));
}

// ─── Widget ──────────────────────────────────────────────────────────────────

/// Section Settings "Diagnostic Logs": Mode Diagnostik (24 jam), Bagikan &
/// Hapus log.
class DiagnosticLogSection extends StatefulWidget {
  final DiagnosticLogActions actions;
  final DateTime Function() now;

  const DiagnosticLogSection({
    super.key,
    DiagnosticLogActions? actions,
    DateTime Function()? now,
  })  : actions = actions ?? const DefaultDiagnosticLogActions(),
        now = now ?? DateTime.now;

  @override
  State<DiagnosticLogSection> createState() => _DiagnosticLogSectionState();
}

class _DiagnosticLogSectionState extends State<DiagnosticLogSection> {
  DateTime? _until;
  LogStats? _stats;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final until = await widget.actions.loadUntil();
    final stats = await widget.actions.stats();
    if (!mounted) return;
    setState(() {
      _until = until;
      _stats = stats;
    });
  }

  bool get _active => DiagnosticMode.isActive(_until, widget.now());

  Future<void> _toggle(bool on) async {
    if (on) {
      final until = await widget.actions.enable();
      if (mounted) setState(() => _until = until);
    } else {
      await widget.actions.disable();
      if (mounted) setState(() => _until = null);
    }
  }

  /// [anchor] = context baris Share Logs: share sheet iOS/iPad berjangkar ke
  /// baris itu.
  Future<void> _share(BuildContext anchor) async {
    setState(() => _sharing = true);
    try {
      await widget.actions.share(anchor);
    } catch (e, stack) {
      logError('Gagal membagikan log', tag: 'LOG', error: e, stack: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal membagikan log: $e'),
          backgroundColor: AppTheme.errorColor,
        ));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
      await _load();
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus semua log?'),
        content: const Text(
            'Berkas log di HP ini akan dihapus. Log baru tetap dicatat.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.actions.clear();
    await _load();
  }

  Widget _icon(IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      );

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final statsText = stats == null
        ? 'Menghitung…'
        : '${stats.files} berkas · ${formatBytes(stats.bytes)}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: AppTheme.getCardDecoration,
      // Material transparan: efek sentuh ListTile tampil di atas latar kartu.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            SwitchListTile(
              key: const ValueKey('diagnostic-toggle'),
              secondary:
                  _icon(Icons.bug_report_outlined, AppTheme.warningColor),
              title: const Text('Diagnostic Mode',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Catat detail tiap fix GPS (lebih boros baterai, otomatis '
                'mati 24 jam) · ${diagnosticStatusLabel(_until, widget.now())}',
                style: const TextStyle(fontSize: 12),
              ),
              value: _active,
              activeColor: AppTheme.primaryColor,
              onChanged: _toggle,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Builder(
              builder: (tileContext) => ListTile(
                key: const ValueKey('share-logs'),
                leading: _icon(Icons.ios_share, AppTheme.primaryBlue),
                title: const Text('Share Logs',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Kirim ke tim (WhatsApp, email, Drive) · $statsText',
                    style: const TextStyle(fontSize: 12)),
                trailing: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_forward_ios_rounded,
                        size: 16, color: Colors.grey),
                onTap: _sharing ? null : () => _share(tileContext),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              key: const ValueKey('clear-logs'),
              leading: _icon(Icons.delete_sweep_outlined, AppTheme.errorColor),
              title: const Text('Clear Logs',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Hapus semua berkas log di HP ini',
                  style: TextStyle(fontSize: 12)),
              onTap: _clear,
            ),
          ],
        ),
      ),
    );
  }
}
