import 'dart:async';

import '../background/notification_service.dart';
import 'session_repository.dart';
import 'tracking_notification.dart';
import 'tracking_session.dart';
import 'tracking_session_manager.dart';

/// Usia maksimum sesi tersimpan yang masih layak dipulihkan. Lebih tua dari ini
/// dianggap ditinggalkan (abandoned) → dibuang saat restore.
const Duration kRestoreMaxAge = Duration(hours: 12);

/// Pisahkan sesi tersimpan menjadi yang layak dipulihkan (keep) dan yang dibuang
/// (drop): buang yang lebih tua dari [maxAge], lalu batasi ke [maxConcurrent]
/// sesi terbaru (berdasarkan startedAt). Mencegah sesi "zombie" dari sesi lama
/// yang tak pernah disimpan memenuhi cap & memblokir Start baru.
({List<TrackingSession> keep, List<TrackingSession> drop}) partitionRestorable(
  List<TrackingSession> all,
  int maxConcurrent,
  DateTime now,
  Duration maxAge,
) {
  final fresh = <TrackingSession>[];
  final drop = <TrackingSession>[];
  for (final s in all) {
    // Kosong (tak ada titik) = tak ada yang bisa dipulihkan; atau terlalu lama.
    if (s.points.isEmpty || now.difference(s.startedAt) > maxAge) {
      drop.add(s);
    } else {
      fresh.add(s);
    }
  }
  fresh.sort((a, b) => b.startedAt.compareTo(a.startedAt)); // terbaru dulu
  if (fresh.length > maxConcurrent) {
    drop.addAll(fresh.sublist(maxConcurrent));
    return (keep: fresh.sublist(0, maxConcurrent), drop: drop);
  }
  return (keep: fresh, drop: drop);
}

/// Berapa titik baru yang belum di-flush untuk sebuah sesi.
int pendingAppendCount(int pointCount, int flushedCount) {
  final n = pointCount - flushedCount;
  return n > 0 ? n : 0;
}

/// projectId yang hilang (sesi berhenti) = ada di [previous] tapi tak di [current].
Set<String> removedIds(Set<String> previous, Set<String> current) =>
    previous.difference(current);

/// Menjembatani [TrackingSessionManager] ↔ [SessionRepository] (persistensi
/// append-only untuk recovery) dan menjaga notifikasi persisten multi-sesi.
///
/// Flush di-debounce agar tak menulis DB tiap fix (hemat I/O). Hot-path UI tetap
/// in-memory di manajer; repo hanya cadangan tahan-lama.
class TrackingPersistenceCoordinator {
  final TrackingSessionManager manager;
  final SessionRepository repo;
  final Duration debounce;
  final void Function(String text) _notify;

  TrackingPersistenceCoordinator({
    TrackingSessionManager? manager,
    SessionRepository? repo,
    this.debounce = const Duration(seconds: 2),
    void Function(String text)? notify,
  })  : manager = manager ?? TrackingSessionManager.instance,
        repo = repo ?? SessionRepository(),
        _notify = notify ??
            ((text) =>
                NotificationService.updateNotification('Terestria Tracking', text));

  final Map<String, int> _flushed = {}; // projectId → jumlah titik ter-flush
  final Map<String, int> _flushedVersion = {}; // projectId → editVersion ter-flush
  Set<String> _knownIds = {};
  Timer? _debounceTimer;
  bool _attached = false;
  int _lastNotifiedCount = -1;

  /// Pulihkan sesi tersimpan ke manajer saat app start. Sesi usang (lebih tua
  /// dari [kRestoreMaxAge]) atau melebihi cap DIBUANG (dihapus dari SQLite) agar
  /// tak jadi "zombie" yang memenuhi cap & memblokir Start.
  Future<void> restore() async {
    final all = await repo.restoreAll();
    final part =
        partitionRestorable(all, manager.maxConcurrent, DateTime.now(), kRestoreMaxAge);
    for (final s in part.drop) {
      await repo.deleteSession(s.projectId);
    }
    // Pulihkan sebagai PAUSED: user memilih "Lanjutkan" sendiri. Mencegah GPS
    // background menyala diam-diam saat app dibuka (dan alur izin iOS yang
    // butuh foreground tetap lewat tombol Resume).
    for (final s in part.keep) {
      if (s.isRecording) s.state = SessionState.paused;
    }
    manager.restoreSessions(part.keep);
    for (final s in part.keep) {
      _flushed[s.projectId] = s.points.length;
    }
    _knownIds = manager.sessions.keys.toSet();
    maybeUpdateNotification();
  }

  /// Mulai mengawasi perubahan manajer.
  void attach() {
    if (_attached) return;
    _attached = true;
    manager.addListener(_onChanged);
  }

  void detach() {
    manager.removeListener(_onChanged);
    _debounceTimer?.cancel();
    _attached = false;
  }

  void _onChanged() {
    maybeUpdateNotification();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, flushNow);
  }

  /// Update notifikasi HANYA saat jumlah sesi aktif berubah — bukan tiap fix GPS
  /// (mencegah spam platform-channel ~1×/detik saat tracking).
  void maybeUpdateNotification() {
    final count = manager.activeCount;
    if (count == _lastNotifiedCount) return;
    _lastNotifiedCount = count;
    final text = trackingNotificationText(count);
    if (text != null) _notify(text);
  }

  /// Flush perubahan ke SQLite: hapus sesi yang berhenti, upsert + append titik baru.
  Future<void> flushNow() async {
    final currentIds = manager.sessions.keys.toSet();

    // Sesi yang berhenti → hapus dari DB.
    for (final id in removedIds(_knownIds, currentIds)) {
      await repo.deleteSession(id);
      _flushed.remove(id);
      _flushedVersion.remove(id);
    }

    // Sesi aktif → upsert + append titik baru.
    for (final s in manager.activeSessions) {
      await repo.upsertSession(s);
      final flushed = _flushed[s.projectId] ?? 0;
      // Snapshot panjang SEBELUM await — bila fix baru tiba saat append berjalan,
      // titik itu tak ikut ter-mark flushed (dikirim di flush berikutnya).
      final len = s.points.length;

      // Undo/clear sejak flush terakhir → posisi append basi; tulis ulang.
      final version = s.editVersion;
      if ((_flushedVersion[s.projectId] ?? 0) != version) {
        await repo.replacePoints(s.projectId, s.points.sublist(0, len));
        _flushed[s.projectId] = len;
        _flushedVersion[s.projectId] = version;
        continue;
      }

      final pending = pendingAppendCount(len, flushed);
      if (pending > 0) {
        await repo.appendPoints(
            s.projectId, s.points.sublist(flushed, len), flushed);
        _flushed[s.projectId] = len;
      }
    }

    _knownIds = currentIds;
  }
}
