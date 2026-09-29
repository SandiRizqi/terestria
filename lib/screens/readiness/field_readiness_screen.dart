import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/geo_data_model.dart';
import '../../services/background/permission_service.dart';
import '../../services/device_health_service.dart';
import '../../services/readiness/field_readiness.dart';
import '../../services/readiness/field_readiness_service.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/ui_feedback.dart';
import '../basemap/basemap_management_screen.dart';
import '../location/location_provider_screen.dart';

/// Checklist "Ready for the field": setiap butir hijau/kuning/merah dengan
/// tombol perbaikan satu ketukan. Dicek ulang otomatis saat kembali dari
/// pengaturan sistem.
class FieldReadinessScreen extends StatefulWidget {
  /// Untuk test: sumber data checklist.
  final Future<ReadinessInputs> Function({bool testGps, GeoPoint? previousFix})?
      collect;

  const FieldReadinessScreen({super.key, this.collect});

  @override
  State<FieldReadinessScreen> createState() => _FieldReadinessScreenState();
}

class _FieldReadinessScreenState extends State<FieldReadinessScreen>
    with WidgetsBindingObserver {
  final FieldReadinessService _service = FieldReadinessService();
  ReadinessInputs? _inputs;
  bool _loading = false;
  bool _testingGps = false;
  bool _syncing = false;
  int _generation = 0;

  Future<ReadinessInputs> _collect({bool testGps = true, GeoPoint? previousFix}) =>
      (widget.collect ?? _service.collect)(
          testGps: testGps, previousFix: previousFix);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh(testGps: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kembali dari Settings sistem → cek ulang (tanpa menunggu GPS).
    if (state == AppLifecycleState.resumed) _refresh(testGps: false);
  }

  /// Dua tahap: cek cepat dulu (langsung tampil), lalu uji GPS.
  Future<void> _refresh({required bool testGps}) async {
    final gen = ++_generation;
    setState(() => _loading = true);
    try {
      final quick =
          await _collect(testGps: false, previousFix: _inputs?.lastFix);
      if (!mounted || gen != _generation) return;
      setState(() {
        _inputs = quick;
        _loading = false;
        _testingGps = testGps;
      });
      if (!testGps) return;
      final full = await _collect(testGps: true, previousFix: quick.lastFix);
      if (!mounted || gen != _generation) return;
      setState(() {
        _inputs = full;
        _testingGps = false;
      });
    } catch (e, st) {
      logError('Readiness check failed', error: e, stack: st, tag: 'READY');
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _testingGps = false;
      });
      showErrorFeedback(context, 'Could not complete the check',
          error: e, stack: st, log: false);
    }
  }

  Future<void> _runFix(ReadinessItem item) async {
    logInfo('Readiness fix "${item.fix.name}" for ${item.id}', tag: 'READY');
    try {
      switch (item.fix) {
        case ReadinessFix.none:
          return;
        case ReadinessFix.requestLocation:
          await Geolocator.requestPermission();
          await _refresh(testGps: true);
        case ReadinessFix.openAppSettings:
          if (!await PermissionService.openAppSettings() && mounted) {
            showInfoFeedback(context,
                'Open Settings → Apps → Terestria to change this.',
                warning: true);
          }
        case ReadinessFix.openLocationSettings:
          if (!await Geolocator.openLocationSettings() && mounted) {
            showInfoFeedback(context,
                'Turn on Location from the quick settings panel.',
                warning: true);
          }
        case ReadinessFix.openBatterySettings:
          final opened =
              await DeviceHealthService().openBatteryOptimizationSettings();
          if (!opened && mounted) {
            showInfoFeedback(
                context,
                item.help ??
                    'Open Battery and choose "Unrestricted" for Terestria.',
                duration: const Duration(seconds: 8));
          }
        case ReadinessFix.openBasemaps:
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const BasemapManagementScreen()));
          if (mounted) await _refresh(testGps: false);
        case ReadinessFix.openLocationProvider:
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const LocationProviderScreen()));
          if (mounted) await _refresh(testGps: false);
        case ReadinessFix.syncNow:
          await _syncNow();
        case ReadinessFix.retestGps:
          await _refresh(testGps: true);
      }
    } catch (e, st) {
      if (mounted) {
        showErrorFeedback(context, 'Could not open that setting',
            error: e, stack: st, tag: 'READY');
      }
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await SyncService().syncAllUnsyncedData();
      if (!mounted) return;
      final ok = !result.hasErrors &&
          !result.abortedDueToConnection &&
          !result.abortedDueToAuth;
      showInfoFeedback(
        context,
        result.abortedDueToAuth
            ? 'Your session expired — sign in again, then sync.'
            : result.abortedDueToConnection
                ? 'The server could not be reached. Try again with a '
                    'better connection.'
                : result.summary,
        success: ok,
        warning: !ok,
        duration: const Duration(seconds: 5),
      );
    } catch (e, st) {
      if (mounted) {
        showErrorFeedback(context, 'Sync failed',
            error: e, stack: st, tag: 'READY');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    if (mounted) await _refresh(testGps: false);
  }

  static IconData _iconFor(String id) => switch (id) {
        'location_permission' => Icons.lock_open_rounded,
        'location_service' => Icons.location_on_rounded,
        'gps_fix' => Icons.gps_fixed_rounded,
        'emlid' => Icons.satellite_alt_rounded,
        'battery' => Icons.battery_charging_full_rounded,
        'notifications' => Icons.notifications_active_rounded,
        'storage' => Icons.sd_storage_rounded,
        'offline_map' => Icons.map_rounded,
        'pending_sync' => Icons.cloud_upload_rounded,
        'unsaved_sessions' => Icons.route_rounded,
        _ => Icons.info_outline_rounded,
      };

  static Color _colorFor(ReadinessLevel level) => switch (level) {
        ReadinessLevel.ok => Colors.green.shade700,
        ReadinessLevel.warning => Colors.orange.shade800,
        ReadinessLevel.problem => Colors.red.shade700,
        ReadinessLevel.info => Colors.blueGrey.shade600,
      };

  static IconData _statusIcon(ReadinessLevel level) => switch (level) {
        ReadinessLevel.ok => Icons.check_circle_rounded,
        ReadinessLevel.warning => Icons.warning_amber_rounded,
        ReadinessLevel.problem => Icons.error_rounded,
        ReadinessLevel.info => Icons.info_rounded,
      };

  Widget _summary(List<ReadinessItem> items) {
    final c = readinessCounts(items);
    final (color, icon, title, subtitle) = c.problems > 0
        ? (
            Colors.red.shade700,
            Icons.error_rounded,
            '${c.problems} problem${c.problems == 1 ? '' : 's'} to fix',
            'Fix the red items before you start collecting.'
          )
        : c.warnings > 0
            ? (
                Colors.orange.shade800,
                Icons.warning_amber_rounded,
                '${c.warnings} ${c.warnings == 1 ? 'item needs' : 'items need'} '
                    'attention',
                'You can go, but check the orange items.'
              )
            : (
                Colors.green.shade700,
                Icons.verified_rounded,
                'Ready for the field',
                'Everything checked is OK.'
              );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(ReadinessItem item) {
    final color = _colorFor(item.level);
    final busy = (item.fix == ReadinessFix.retestGps && _testingGps) ||
        (item.fix == ReadinessFix.syncNow && _syncing);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_iconFor(item.id), color: Colors.grey.shade700, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(item.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        Icon(_statusIcon(item.level), color: color, size: 22),
                      ]),
                      const SizedBox(height: 4),
                      Text(item.detail,
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade800)),
                    ],
                  ),
                ),
              ],
            ),
            if (item.help != null && item.level != ReadinessLevel.ok) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(item.help!,
                    style: const TextStyle(fontSize: 13, height: 1.3)),
              ),
            ],
            if (item.fix != ReadinessFix.none && item.fixLabel != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: busy ? null : () => _runFix(item),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(item.fixLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputs = _inputs;
    final items = inputs == null ? const <ReadinessItem>[] : evaluateReadiness(inputs);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ready for the field'),
        actions: [
          IconButton(
            tooltip: 'Check again',
            onPressed: _loading ? null : () => _refresh(testGps: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: inputs == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppTheme.primaryColor,
              onRefresh: () => _refresh(testGps: true),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _summary(items),
                  if (_testingGps)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  for (final item in items) _tile(item),
                ],
              ),
            ),
    );
  }
}
