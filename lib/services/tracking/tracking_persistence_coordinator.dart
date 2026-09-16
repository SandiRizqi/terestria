import 'dart:async';

import '../background/notification_service.dart';
import 'session_repository.dart';
import 'tracking_notification.dart';
import 'tracking_session_manager.dart';

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

  TrackingPersistenceCoordinator({
    TrackingSessionManager? manager,
    SessionRepository? repo,
    this.debounce = const Duration(seconds: 2),
  })  : manager = manager ?? TrackingSessionManager.instance,
        repo = repo ?? SessionRepository();

  final Map<String, int> _flushed = {}; // projectId → jumlah titik ter-flush
  Set<String> _knownIds = {};
  Timer? _debounceTimer;
  bool _attached = false;

  /// Pulihkan sesi tersimpan ke manajer saat app start.
  Future<void> restore() async {
    final sessions = await repo.restoreAll();
    manager.restoreSessions(sessions);
    for (final s in sessions) {
      _flushed[s.projectId] = s.points.length;
    }
    _knownIds = manager.sessions.keys.toSet();
    _updateNotification();
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
    _updateNotification();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, flushNow);
  }

  void _updateNotification() {
    final text = trackingNotificationText(manager.activeCount);
    if (text != null) {
      NotificationService.updateNotification('Terestria Tracking', text);
    }
  }

  /// Flush perubahan ke SQLite: hapus sesi yang berhenti, upsert + append titik baru.
  Future<void> flushNow() async {
    final currentIds = manager.sessions.keys.toSet();

    // Sesi yang berhenti → hapus dari DB.
    for (final id in removedIds(_knownIds, currentIds)) {
      await repo.deleteSession(id);
      _flushed.remove(id);
    }

    // Sesi aktif → upsert + append titik baru.
    for (final s in manager.activeSessions) {
      await repo.upsertSession(s);
      final flushed = _flushed[s.projectId] ?? 0;
      final pending = pendingAppendCount(s.points.length, flushed);
      if (pending > 0) {
        await repo.appendPoints(
            s.projectId, s.points.sublist(flushed), flushed);
        _flushed[s.projectId] = s.points.length;
      }
    }

    _knownIds = currentIds;
  }
}
