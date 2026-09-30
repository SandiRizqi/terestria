import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/project_model.dart';
import '../../services/auto_sync_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/readiness/field_readiness.dart';
import '../../services/readiness/field_readiness_service.dart';
import '../../services/settings_service.dart';
import '../../services/sync_service.dart';
import '../sync/sync_result_dialog.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/ui_feedback.dart';
import '../tracking/active_tracking_panel.dart';

/// Kartu status di beranda: tracking aktif, kesiapan lapangan, dan antrean
/// sync (dengan tombol "Sync now"). Data diambil dari [FieldReadinessService]
/// tanpa uji GPS (cepat).
/// Subjudul kartu sync saat auto-sync terakhir gagal: sebut alasan pertama
/// (mis. project nonaktif) — ketuk kartu untuk semua alasan.
String lastAutoSyncSubtitle(AutoSyncRun run, String time) =>
    run.reasons.isNotEmpty
        ? 'Last auto-sync $time failed: ${run.reasons.first}'
        : 'Last auto-sync $time: ${run.summary}';

class HomeStatusSection extends StatefulWidget {
  final void Function(Project) onOpenProject;
  final VoidCallback onOpenReadiness;

  /// Untuk test: sumber data kartu (default: cek cepat tanpa GPS).
  final Future<ReadinessInputs> Function()? collect;

  const HomeStatusSection({
    super.key,
    required this.onOpenProject,
    required this.onOpenReadiness,
    this.collect,
  });

  @override
  State<HomeStatusSection> createState() => HomeStatusSectionState();
}

class HomeStatusSectionState extends State<HomeStatusSection> {
  final SyncService _sync = SyncService();
  ReadinessInputs? _inputs;
  bool _loading = false;
  bool _syncing = false;
  String? _progress;
  double? _progressValue;
  bool _online = ConnectivityService().isOnline;
  StreamSubscription<bool>? _onlineSub;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _onlineSub = ConnectivityService().connectivityStream.listen((online) {
      if (mounted) setState(() => _online = online);
    });
    // Sync lain (auto-sync, layar project) selesai → hitung ulang antrean.
    _sync.isSyncing.addListener(_onSyncingChanged);
    refresh();
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    _sync.isSyncing.removeListener(_onSyncingChanged);
    super.dispose();
  }

  void _onSyncingChanged() {
    final now = _sync.isSyncing.value;
    if (_wasSyncing && !now) refresh();
    _wasSyncing = now;
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final inputs = await (widget.collect ??
          () => FieldReadinessService().collect(testGps: false))();
      if (mounted) setState(() => _inputs = inputs);
    } catch (e, st) {
      logWarn('Home status refresh failed', tag: 'HOME', error: e, stack: st);
    } finally {
      _loading = false;
    }
  }

  Future<void> _syncNow() async {
    if (_syncing || _sync.isSyncing.value) return;
    setState(() {
      _syncing = true;
      _progress = 'Starting…';
      _progressValue = null;
    });
    try {
      final result = await _sync.syncAllUnsyncedData(
        onProgress: (message, {done, total}) {
          if (!mounted) return;
          setState(() {
            _progress = message;
            _progressValue =
                (done != null && total != null && total > 0) ? done / total : null;
          });
        },
      );
      if (!mounted) return;
      // Gagal sebagian → dialog berisi alasannya (mis. project nonaktif).
      await showFullSyncResult(context, result, onRetry: _syncNow);
    } catch (e, st) {
      if (mounted) {
        showErrorFeedback(context, 'Sync failed',
            error: e, stack: st, tag: 'HOME');
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _progress = null;
          _progressValue = null;
        });
      }
    }
    await refresh();
  }

  Widget _card({
    required Color color,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Widget? bottom,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(subtitle,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) trailing,
                  ],
                ),
                if (bottom != null) bottom,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _readinessCard(ReadinessInputs inputs) {
    final items = evaluateReadiness(inputs);
    final c = readinessCounts(items);
    final attention = items
        .where((i) =>
            i.level == ReadinessLevel.problem ||
            i.level == ReadinessLevel.warning)
        .where((i) => i.id != 'pending_sync') // ada kartu sendiri
        .map((i) => i.title)
        .toList();
    final problems = c.problems;
    final warnings = attention.length - problems;
    final (color, icon, title) = problems > 0
        ? (
            Colors.red.shade700,
            Icons.error_rounded,
            '$problems problem${problems == 1 ? '' : 's'} before the field'
          )
        : warnings > 0
            ? (
                Colors.orange.shade800,
                Icons.warning_amber_rounded,
                '$warnings ${warnings == 1 ? 'item needs' : 'items need'} '
                    'attention'
              )
            : (
                Colors.green.shade700,
                Icons.verified_rounded,
                'Ready for the field'
              );
    return _card(
      color: color,
      icon: icon,
      title: title,
      subtitle: attention.isEmpty
          ? 'Permissions, GPS, battery and storage look good'
          : attention.take(3).join(' · '),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: widget.onOpenReadiness,
    );
  }

  Widget _syncCard(ReadinessInputs inputs) {
    final records = inputs.unsyncedRecords;
    final photos = inputs.pendingPhotos;
    final busy = _syncing || _sync.isSyncing.value;
    final autoSync = SettingsService().settings.autoSyncWhenOnline;
    final lastAuto = AutoSyncService.instance.lastRun.value;

    if (records == 0 && photos == 0 && !busy) {
      return _card(
        color: Colors.green.shade700,
        icon: Icons.cloud_done_rounded,
        title: 'Everything is synced',
        subtitle: autoSync ? 'Auto-sync is on' : null,
      );
    }
    final parts = [
      if (records > 0) '$records record${records == 1 ? '' : 's'}',
      if (photos > 0) '$photos photo${photos == 1 ? '' : 's'}',
    ];
    String? subtitle;
    if (busy) {
      subtitle = _progress ?? 'Syncing in the background…';
    } else if (!_online) {
      subtitle = 'Offline — your data is safe on this phone';
    } else if (lastAuto != null && !lastAuto.ok) {
      final t = TimeOfDay.fromDateTime(lastAuto.at).format(context);
      subtitle = lastAutoSyncSubtitle(lastAuto, t);
    } else if (autoSync) {
      subtitle = 'Auto-sync will upload these when online';
    }
    final failedAuto =
        !busy && lastAuto != null && !lastAuto.ok && lastAuto.reasons.isNotEmpty;
    return _card(
      color: AppTheme.primaryBlue,
      icon: Icons.cloud_upload_rounded,
      title: parts.isEmpty ? 'Syncing…' : '${parts.join(' · ')} waiting',
      subtitle: subtitle,
      // Ketuk → semua alasan auto-sync terakhir gagal.
      onTap: failedAuto
          ? () => showSyncProblemsDialog(
                context,
                title: 'Last auto-sync did not finish',
                summary: lastAuto.summary,
                errors: lastAuto.reasons,
              )
          : null,
      trailing: FilledButton(
        onPressed: busy || !_online ? null : _syncNow,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          backgroundColor: AppTheme.primaryColor,
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Text('Sync now'),
      ),
      bottom: busy
          ? Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                  value: _progressValue, minHeight: 4),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputs = _inputs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner sesi tracking (sembunyi sendiri bila tak ada sesi).
        ActiveTrackingBanner(
          padding: const EdgeInsets.only(bottom: 10),
          onTap: () => showActiveTrackingPanel(
            context,
            onOpenProject: widget.onOpenProject,
          ),
        ),
        if (inputs == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 3),
          )
        else ...[
          _readinessCard(inputs),
          _syncCard(inputs),
        ],
      ],
    );
  }
}
