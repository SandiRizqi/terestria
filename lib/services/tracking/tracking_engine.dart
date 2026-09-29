import 'dart:async';

import '../../models/geo_data_model.dart';
import '../../utils/app_logger.dart';
import '../location_service_v2.dart';
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
    this.heartbeatInterval = const Duration(seconds: 5),
    this.restartBackoff = const Duration(seconds: 30),
  })  : _phoneFeed = phoneFeed,
        _emlidFeed = emlidFeed,
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
    stopService: () async {
      await LocationServiceV2().stopBackgroundTracking();
      await LocationServiceV2().stopActiveTracking();
    },
    sendHeartbeat: () => LocationServiceV2().sendHeartbeat(),
    isServiceRunning: () => LocationServiceV2().isBackgroundServiceRunning,
    phoneFeed: LocationServiceV2().backgroundLocationStream,
    emlidFeed: LocationServiceV2().emlidLocationStream,
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
  final List<StreamSubscription<GeoPoint>> _feedSubs = [];

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
    if (want == _active) return;
    _active = want;
    if (want) {
      _heartbeat?.cancel();
      _heartbeat = _periodicTimer(heartbeatInterval, (_) => tick());
      _sendHeartbeat();
      _subscribeFeeds();
      unawaited(ensureRunning());
    } else {
      _heartbeat?.cancel();
      _heartbeat = null;
      _unsubscribeFeeds();
      unawaited(_stop());
    }
  }

  /// SATU-SATUNYA jalur titik ke sesi: feed HP (background service) dan feed
  /// RTK (socket Emlid) masing-masing hanya masuk ke sesi bersumber sama.
  /// Tak bergantung pada layar mana pun yang terbuka.
  void _subscribeFeeds() {
    _unsubscribeFeeds();
    final phone = _phoneFeed;
    if (phone != null) {
      _feedSubs.add(phone.listen(
          (p) => manager.ingest(p, source: TrackSource.phone)));
    }
    final emlid = _emlidFeed;
    if (emlid != null) {
      _feedSubs.add(emlid.listen(
          (p) => manager.ingest(p, source: TrackSource.emlid)));
    }
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
    } catch (e) {
      logError('❌ TrackingEngine: gagal menghentikan service: $e');
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
      return await _startService();
    } catch (e) {
      logError('❌ TrackingEngine: gagal menyalakan service: $e');
      return false;
    }
  }

  /// Detak periodik: kirim heartbeat & pulihkan service yang mati sendiri
  /// (dengan backoff agar tak membanjiri permintaan izin bila terus gagal).
  void tick() {
    if (!_active) return;
    _sendHeartbeat();
    if (_starting != null || _isServiceRunning()) return;
    final now = _now();
    final last = _lastRestartAttempt;
    if (last != null && now.difference(last) < restartBackoff) return;
    _lastRestartAttempt = now;
    logError('⚠️ TrackingEngine: service mati saat sesi merekam → start ulang');
    unawaited(ensureRunning());
  }
}
