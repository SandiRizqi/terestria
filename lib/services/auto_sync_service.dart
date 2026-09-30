import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';
import 'sync_service.dart';

/// Ringkasan run auto-sync terakhir (untuk kartu status di beranda).
class AutoSyncRun {
  final DateTime at;
  final bool ok;
  final String summary;

  /// Alasan gagal (dikelompokkan) — ditampilkan di beranda.
  final List<String> reasons;

  const AutoSyncRun({
    required this.at,
    required this.ok,
    required this.summary,
    this.reasons = const [],
  });
}

/// Unggah data tertunda otomatis saat online (Settings → "Auto-sync when
/// online"). Hanya berjalan saat app terbuka; memakai
/// [SyncService.runExclusive] sehingga tak pernah tumpang tindih dengan sync
/// manual. Gagal beruntun → jeda bertambah (1, 2, 4 … maks 30 menit).
class AutoSyncService {
  AutoSyncService({
    bool Function()? isOnline,
    Stream<bool>? onlineChanges,
    Future<FullSyncResult> Function()? syncAll,
    ValueListenable<bool>? isSyncing,
    bool Function()? enabled,
    Future<int> Function()? pendingCount,
    bool Function()? authBlocked,
    Future<bool> Function()? loggedIn,
    DateTime Function()? now,
    this.debounce = const Duration(seconds: 15),
    this.retryInterval = const Duration(minutes: 15),
  })  : _isOnline = isOnline ?? (() => ConnectivityService().isOnline),
        _onlineChanges =
            onlineChanges ?? ConnectivityService().connectivityStream,
        _syncAll = syncAll ?? (() => SyncService().syncAllUnsyncedData()),
        _isSyncing = isSyncing ?? SyncService().isSyncing,
        _enabled =
            enabled ?? (() => SettingsService().settings.autoSyncWhenOnline),
        _pendingCount = pendingCount ?? _defaultPendingCount,
        _authBlocked = authBlocked ?? (() => AuthService().tokenRejected),
        _loggedIn = loggedIn ??
            (() async => (await AuthService().getToken()) != null),
        _now = now ?? DateTime.now;

  static final AutoSyncService instance = AutoSyncService();

  final bool Function() _isOnline;
  final Stream<bool> _onlineChanges;
  final Future<FullSyncResult> Function() _syncAll;
  final ValueListenable<bool> _isSyncing;
  final bool Function() _enabled;
  final Future<int> Function() _pendingCount;
  final bool Function() _authBlocked;
  final Future<bool> Function() _loggedIn;
  final DateTime Function() _now;
  final Duration debounce;
  final Duration retryInterval;

  static const _tag = 'AUTOSYNC';

  /// Run terakhir (null = belum pernah di sesi app ini).
  final ValueNotifier<AutoSyncRun?> lastRun = ValueNotifier<AutoSyncRun?>(null);

  StreamSubscription<bool>? _connectivitySub;
  Timer? _debounceTimer;
  Timer? _periodic;
  bool _running = false;
  int _failures = 0;
  DateTime? _lastFailureAt;

  bool get isStarted => _connectivitySub != null;

  static Future<int> _defaultPendingCount() async {
    final storage = StorageService();
    // Record berkonflik menunggu keputusan user — bukan antrean otomatis.
    final records = await storage.getUnsyncedGeoDataCount() -
        await storage.getSyncConflictCount();
    return (records < 0 ? 0 : records) +
        await storage.getUnsyncedProjectCount();
  }

  /// Jeda setelah [failures] kegagalan beruntun.
  static Duration backoffFor(int failures) => failures <= 0
      ? Duration.zero
      : Duration(minutes: math.min(30, 1 << math.min(failures - 1, 5)));

  void start() {
    if (isStarted) return;
    _connectivitySub = _onlineChanges.listen((online) {
      if (online) schedule('back online');
    });
    _periodic = Timer.periodic(retryInterval, (_) => schedule('periodic'));
    SettingsService().addListener(_onSettingsChanged);
    logDebug('Auto-sync watcher started', tag: _tag);
    if (_isOnline()) schedule('app opened');
  }

  void stop() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _periodic?.cancel();
    _periodic = null;
    try {
      SettingsService().removeListener(_onSettingsChanged);
    } catch (_) {}
    logDebug('Auto-sync watcher stopped', tag: _tag);
  }

  /// Lupakan riwayat user yang logout: hitungan gagal (backoff) dan status
  /// run terakhir — user berikutnya tak mewarisi jeda sampai 30 menit maupun
  /// status "sync terakhir gagal" milik user lama.
  void reset() {
    _failures = 0;
    _lastFailureAt = null;
    lastRun.value = null;
  }

  void _onSettingsChanged() {
    if (_enabled() && _isOnline()) schedule('enabled');
  }

  /// Jadwalkan run setelah [debounce] (koneksi sering naik-turun di lapangan).
  void schedule(String reason) {
    if (!_enabled()) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => runNow(reason));
  }

  /// Jalankan bila syaratnya terpenuhi. Mengembalikan true bila sync berjalan.
  Future<bool> runNow(String reason) async {
    if (_running || !_enabled()) return false;
    if (!_isOnline()) return false;
    if (_authBlocked()) {
      logDebug('Auto-sync skipped ($reason): session expired', tag: _tag);
      return false;
    }
    if (_isSyncing.value) return false; // sync manual sedang berjalan
    final wait = backoffFor(_failures);
    if (_lastFailureAt != null && _now().difference(_lastFailureAt!) < wait) {
      logDebug('Auto-sync skipped ($reason): backing off ${wait.inMinutes} min',
          tag: _tag);
      return false;
    }

    _running = true;
    try {
      if (!await _loggedIn()) return false;
      final pending = await _pendingCount();
      if (pending == 0) return false;
      logInfo('Auto-sync ($reason): $pending item(s) pending', tag: _tag);
      final result = await _syncAll();
      final ok = !result.hasErrors &&
          !result.abortedDueToConnection &&
          !result.abortedDueToAuth;
      final summary = result.abortedDueToAuth
          ? 'Session expired'
          : result.abortedDueToConnection
              ? 'Server not reachable'
              : result.summary;
      if (ok) {
        _failures = 0;
        _lastFailureAt = null;
        logInfo('Auto-sync done: $summary', tag: _tag);
      } else {
        _failures++;
        _lastFailureAt = _now();
        logWarn('Auto-sync incomplete ($_failures in a row): $summary'
            '${result.errors.isEmpty ? '' : ' — ${result.errors.take(3).join('; ')}'}',
            tag: _tag);
      }
      lastRun.value = AutoSyncRun(
        at: _now(),
        ok: ok,
        summary: summary,
        reasons: ok ? const [] : SyncService.groupErrors(result.errors),
      );
      return true;
    } catch (e, st) {
      _failures++;
      _lastFailureAt = _now();
      logError('Auto-sync failed', tag: _tag, error: e, stack: st);
      lastRun.value =
          AutoSyncRun(at: _now(), ok: false, summary: 'Sync failed');
      return true;
    } finally {
      _running = false;
    }
  }
}
