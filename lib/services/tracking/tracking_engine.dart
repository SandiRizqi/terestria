import 'dart:async';

import '../../models/geo_data_model.dart';
import '../../utils/app_logger.dart';
import '../location_service_v2.dart';
import 'tracking_log_summary.dart';
import 'tracking_notification.dart';
import 'tracking_session.dart';
import 'tracking_session_manager.dart';

/// Pemilik TUNGGAL feed GPS tracking di level app (bukan layar).
///
/// Menyalakan background service + heartbeat saat ada sesi yang merekam
/// (`recordingCount` 0→>0) dan mematikannya saat tak ada lagi. Dulu heartbeat
/// dikirim oleh `DataCollectionScreen`, sehingga menutup layar membuat isolate
/// mematikan diri ±15 dtk kemudian dan titik semua project berhenti terekam.
///
/// Semua efek samping lewat port yang disuntik agar bisa diuji tanpa plugin.
class TrackingEngine {
  TrackingEngine({
    required this.manager,
    required Future<bool> Function() startService,
    required Future<void> Function() stopService,
    required void Function() sendHeartbeat,
    required bool Function() isServiceRunning,
    Timer Function(Duration, void Function(Timer))? periodicTimer,
    DateTime Function()? now,
    Stream<GeoPoint>? phoneFeed,
    Stream<GeoPoint>? emlidFeed,
    void Function(String text)? setNotificationText,
    Future<void> Function()? onFeedStart,
    Future<void> Function()? onFeedStop,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.restartBackoff = const Duration(seconds: 30),
  })  : _phoneFeed = phoneFeed,
        _emlidFeed = emlidFeed,
        _setNotificationText = setNotificationText,
        _onFeedStart = onFeedStart,
        _onFeedStop = onFeedStop,
        _startService = startService,
        _stopService = stopService,
        _sendHeartbeat = sendHeartbeat,
        _isServiceRunning = isServiceRunning,
        _periodicTimer = periodicTimer ?? Timer.periodic,
        _now = now ?? DateTime.now;

  /// Engine produksi: port ke [LocationServiceV2] + manajer bersama.
  static final TrackingEngine instance = TrackingEngine(
    manager: TrackingSessionManager.instance,
    startService: () => LocationServiceV2().startBackgroundTracking(),
    stopService: () => LocationServiceV2().stopBackgroundTracking(),
    sendHeartbeat: () => LocationServiceV2().sendHeartbeat(),
    isServiceRunning: () => LocationServiceV2().isBackgroundServiceRunning,
    phoneFeed: LocationServiceV2().backgroundLocationStream,
    emlidFeed: LocationServiceV2().emlidLocationStream,
    setNotificationText: (t) => LocationServiceV2().setTrackingNotificationText(t),
    onFeedStart: () => LocationServiceV2().startGpsLog(),
    onFeedStop: () => LocationServiceV2().stopGpsLog(),
  );

  final TrackingSessionManager manager;
  final Duration heartbeatInterval;
  final Duration restartBackoff;
  final Future<bool> Function() _startService;
  final Future<void> Function() _stopService;
  final void Function() _sendHeartbeat;
  final bool Function() _isServiceRunning;
  final Timer Function(Duration, void Function(Timer)) _periodicTimer;
  final DateTime Function() _now;
  final Stream<GeoPoint>? _phoneFeed;
  final Stream<GeoPoint>? _emlidFeed;
  final void Function(String text)? _setNotificationText;
  final Future<void> Function()? _onFeedStart;
  final Future<void> Function()? _onFeedStop;
  final List<StreamSubscription<GeoPoint>> _feedSubs = [];
  String? _lastLabel;
  TrackingLogSummary? _summary; // ringkasan GPS per menit selama aktif

  static const _tag = 'ENGINE';

  bool _attached = false;
  bool _active = false;
  Timer? _heartbeat;
  Future<bool>? _starting;
  DateTime? _lastRestartAttempt;

  /// True selama ada sesi merekam (service + heartbeat seharusnya hidup).
  bool get isActive => _active;

  void attach() {
    if (_attached) return;
    _attached = true;
    manager.addListener(_onChanged);
    _onChanged();
  }

  void detach() {
    manager.removeListener(_onChanged);
    _attached = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    _unsubscribeFeeds();
    _active = false;
  }

  void _onChanged() {
    final want = manager.recordingCount > 0;
    if (want != _active) {
      _active = want;
      if (want) {
        logInfo('Aktif (${manager.recordingCount} merekam)', tag: _tag);
        _summary = TrackingLogSummary(start: _now());
        _heartbeat?.cancel();
        _heartbeat = _periodicTimer(heartbeatInterval, (_) => tick());
        _sendHeartbeat();
        _subscribeFeeds();
        unawaited(_safely(_onFeedStart));
        unawaited(ensureRunning());
      } else {
        logInfo('Idle — tak ada sesi merekam, service dimatikan', tag: _tag);
        _summary = null;
        _heartbeat?.cancel();
        _heartbeat = null;
        _unsubscribeFeeds();
        unawaited(_safely(_onFeedStop));
        unawaited(_stop());
      }
    }
    _pushLabel();
  }

  /// Kirim ringkasan status ke notifikasi service — hanya bila teksnya
  /// berubah (bukan tiap titik), atau [force] setelah service (re)start.
  void _pushLabel({bool force = false}) {
    final send = _setNotificationText;
    if (send == null) return;
    if (!_active) {
      _lastLabel = null;
      return;
    }
    final text = trackingNotificationText(
      recording: manager.recordingCount,
      paused: manager.liveCount - manager.recordingCount,
      pending: manager.activeCount - manager.liveCount,
    );
    if (text == null || (!force && text == _lastLabel)) return;
    _lastLabel = text;
    send(text);
  }

  Future<void> _safely(Future<void> Function()? f) async {
    if (f == null) return;
    try {
      await f();
    } catch (e) {
      logError('Hook engine gagal', tag: _tag, error: e);
    }
  }

  /// SATU-SATUNYA jalur titik ke sesi: feed HP (background service) dan feed
  /// RTK (socket Emlid) masing-masing hanya masuk ke sesi bersumber sama.
  /// Tak bergantung pada layar mana pun yang terbuka.
  void _subscribeFeeds() {
    _unsubscribeFeeds();
    final phone = _phoneFeed;
    if (phone != null) {
      _feedSubs.add(phone.listen((p) => _onFix(p, TrackSource.phone)));
    }
    final emlid = _emlidFeed;
    if (emlid != null) {
      _feedSubs.add(emlid.listen((p) => _onFix(p, TrackSource.emlid)));
    }
  }

  void _onFix(GeoPoint p, TrackSource source) {
    _summary?.onFix(source, p);
    logDebug(
        'fix ${source.name} ${p.latitude},${p.longitude} '
        '±${p.accuracy?.toStringAsFixed(1) ?? '?'} m '
        '${p.recordable ? 'rekam' : 'tolak'}',
        tag: 'GPS');
    manager.ingest(p, source: source);
  }

  void _unsubscribeFeeds() {
    for (final s in _feedSubs) {
      s.cancel();
    }
    _feedSubs.clear();
  }

  Future<void> _stop() async {
    try {
      await _stopService();
    } catch (e, stack) {
      logError('Gagal menghentikan service', tag: _tag, error: e, stack: stack);
    }
  }

  /// Pastikan background service jalan. Panggilan bersamaan berbagi satu
  /// proses start. Mengembalikan false bila service gagal dinyalakan (layar
  /// menampilkan dialog error & me-rollback sesinya).
  Future<bool> ensureRunning() {
    if (_starting != null) return _starting!;
    if (_isServiceRunning()) return Future.value(true);
    final f = _startSafely();
    _starting = f;
    f.whenComplete(() => _starting = null);
    return f;
  }

  Future<bool> _startSafely() async {
    try {
      final ok = await _startService();
      if (ok) {
        logInfo('Service menyala', tag: _tag);
        // Service baru menyala dengan teks default → kirim ulang ringkasan.
        _pushLabel(force: true);
      } else {
        logWarn('Service gagal dinyalakan (izin/lokasi mati?)', tag: _tag);
      }
      return ok;
    } catch (e, stack) {
      logError('Gagal menyalakan service', tag: _tag, error: e, stack: stack);
      return false;
    }
  }

  /// Detak periodik: kirim heartbeat & pulihkan service yang mati sendiri
  /// (dengan backoff agar tak membanjiri permintaan izin bila terus gagal).
  void tick() {
    if (!_active) return;
    _sendHeartbeat();
    final now = _now();
    final summary = _summary?.maybeSummary(now, manager.activeSessions);
    if (summary != null) logInfo(summary, tag: 'GPS');

    if (_starting != null || _isServiceRunning()) return;
    final last = _lastRestartAttempt;
    if (last != null && now.difference(last) < restartBackoff) return;
    _lastRestartAttempt = now;
    logWarn('Service mati saat sesi merekam → start ulang', tag: _tag);
    unawaited(ensureRunning());
  }
}
