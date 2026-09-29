import 'dart:async';

import '../../utils/app_logger.dart';
import 'session_repository.dart';
import 'tracking_session.dart';
import 'tracking_session_manager.dart';

/// Usia sesi tersimpan yang dianggap "lama". Sesi lama TIDAK dibuang (titiknya
/// bisa berisi kerja lapangan berjam-jam) — dipulihkan sebagai draft
/// (pendingSave) agar tak memenuhi cap; user memilih Simpan/Buang sendiri.
const Duration kRestoreMaxAge = Duration(hours: 12);

/// Hasil pemilahan sesi tersimpan saat restore.
///
/// - [keep]    : dipulihkan ke manajer (termasuk yang di-[demoted]).
/// - [drop]    : dibuang dari SQLite — HANYA sesi tanpa titik.
/// - [demoted] : subset [keep] yang dijadikan draft (pendingSave) karena
///               lama (> maxAge) atau melebihi cap sesi live.
typedef RestorePartition = ({
  List<TrackingSession> keep,
  List<TrackingSession> drop,
  List<TrackingSession> demoted,
});

/// Pilah sesi tersimpan untuk restore TANPA kehilangan data:
/// sesi berisi titik selalu dipulihkan. Draft (pendingSave) tak dihitung ke
/// cap — sama seperti saat app berjalan. Sesi live (recording/paused) yang lama
/// atau melebihi [maxConcurrent] (yang terbaru didahulukan) dijadikan draft,
/// bukan dihapus, supaya tak ada sesi "zombie" yang memblokir Start baru.
RestorePartition partitionRestorable(
  List<TrackingSession> all,
  int maxConcurrent,
  DateTime now,
  Duration maxAge,
) {
  final keep = <TrackingSession>[];
  final drop = <TrackingSession>[];
  final demoted = <TrackingSession>[];
  final live = <TrackingSession>[];

  for (final s in all) {
    if (s.points.isEmpty) {
      drop.add(s); // tak ada yang bisa dipulihkan
      continue;
    }
    keep.add(s);
    if (s.pendingSave) continue; // draft: tak dihitung cap
    if (now.difference(s.startedAt) > maxAge) {
      demoted.add(s);
    } else {
      live.add(s);
    }
  }

  live.sort((a, b) => b.startedAt.compareTo(a.startedAt)); // terbaru dulu
  if (live.length > maxConcurrent) {
    demoted.addAll(live.sublist(maxConcurrent));
  }
  return (keep: keep, drop: drop, demoted: demoted);
}

/// Berapa titik baru yang belum di-flush untuk sebuah sesi.
int pendingAppendCount(int pointCount, int flushedCount) {
  final n = pointCount - flushedCount;
  return n > 0 ? n : 0;
}

/// projectId yang hilang (sesi berhenti) = ada di [previous] tapi tak di [current].
Set<String> removedIds(Set<String> previous, Set<String> current) =>
    previous.difference(current);

/// Jeda sebelum flush terjadwal: [debounce] biasa, tapi tak pernah melewati
/// [maxWait] sejak perubahan PERTAMA yang belum di-flush. Tanpa batas ini,
/// fix GPS tiap ±1 dtk terus me-reset debounce dan flush tak pernah jalan
/// selama surveyor bergerak.
Duration nextFlushDelay({
  required Duration sinceFirstPending,
  required Duration debounce,
  required Duration maxWait,
}) {
  final remaining = maxWait - sinceFirstPending;
  if (remaining <= Duration.zero) return Duration.zero;
  return remaining < debounce ? remaining : debounce;
}

/// Menjembatani [TrackingSessionManager] ↔ [SessionRepository] (persistensi
/// append-only untuk recovery). Notifikasi dikelola TrackingEngine.
///
/// Flush di-debounce agar tak menulis DB tiap fix (hemat I/O), dengan batas
/// [maxWait] agar titik yang terus berdatangan tetap tersimpan berkala. Hot-path
/// UI tetap in-memory di manajer; repo hanya cadangan tahan-lama.
class TrackingPersistenceCoordinator {
  final TrackingSessionManager manager;
  final SessionRepository repo;
  final Duration debounce;
  final Duration maxWait;
  final Timer Function(Duration, void Function()) _timer;
  final DateTime Function() _now;

  static const _tag = 'PERSIST';

  TrackingPersistenceCoordinator({
    TrackingSessionManager? manager,
    SessionRepository? repo,
    this.debounce = const Duration(seconds: 2),
    this.maxWait = const Duration(seconds: 8),
    Timer Function(Duration, void Function())? timer,
    DateTime Function()? now,
  })  : manager = manager ?? TrackingSessionManager.instance,
        repo = repo ?? SessionRepository(),
        _timer = timer ?? Timer.new,
        _now = now ?? DateTime.now;

  final Map<String, int> _flushed = {}; // projectId → jumlah titik ter-flush
  final Map<String, int> _flushedVersion = {}; // projectId → editVersion ter-flush
  Set<String> _knownIds = {};
  Timer? _debounceTimer;
  DateTime? _firstPendingAt; // perubahan pertama yang belum di-flush
  Future<void>? _inFlight; // flush berjalan (flush diserialkan)
  bool _attached = false;

  /// Ringkasan restore terakhir (untuk UI: "N sesi dipulihkan").
  RestorePartition? lastRestore;

  /// Pulihkan sesi tersimpan ke manajer saat app start. Sesi berisi titik
  /// tak pernah dibuang; lihat [partitionRestorable].
  Future<void> restore() async {
    final all = await repo.restoreAll();
    final part = partitionRestorable(
        all, manager.maxConcurrent, _now(), kRestoreMaxAge);
    for (final s in part.drop) {
      try {
        await repo.deleteSession(s.projectId);
      } catch (e, st) {
        logError('Failed to delete empty session ${s.projectId}',
            tag: _tag, error: e, stack: st);
      }
    }
    // Pulihkan sebagai PAUSED: user memilih "Lanjutkan" sendiri. Mencegah GPS
    // background menyala diam-diam saat app dibuka (dan alur izin iOS yang
    // butuh foreground tetap lewat tombol Resume).
    for (final s in part.keep) {
      if (s.isRecording) s.state = SessionState.paused;
    }
    for (final s in part.demoted) {
      s.state = SessionState.pendingSave;
    }
    manager.restoreSessions(part.keep);
    for (final s in part.keep) {
      _flushed[s.projectId] = s.points.length;
      // Status sesi (mis. hasil demote) ditulis ulang pada flush berikutnya.
      _flushedVersion[s.projectId] = s.editVersion;
    }
    _knownIds = manager.sessions.keys.toSet();
    lastRestore = part;
    if (part.keep.isNotEmpty || part.drop.isNotEmpty) {
      logInfo(
          'Restore: ${part.keep.length} kept '
          '(${part.demoted.length} moved to drafts), '
          '${part.drop.length} empty removed',
          tag: _tag);
    }
    if (part.demoted.isNotEmpty) {
      // Simpan status draft segera agar konsisten bila app mati lagi.
      await flushNow();
    }
  }

  /// Koordinator yang sedang terpasang (dipakai reset app untuk flush).
  static TrackingPersistenceCoordinator? active;

  /// Mulai mengawasi perubahan manajer.
  void attach() {
    if (_attached) return;
    _attached = true;
    active = this;
    manager.addListener(_onChanged);
  }

  void detach() {
    manager.removeListener(_onChanged);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _firstPendingAt = null;
    _attached = false;
    if (identical(active, this)) active = null;
  }

  void _onChanged() {
    final now = _now();
    _firstPendingAt ??= now;
    _debounceTimer?.cancel();
    _debounceTimer = _timer(
      nextFlushDelay(
        sinceFirstPending: now.difference(_firstPendingAt!),
        debounce: debounce,
        maxWait: maxWait,
      ),
      _flushScheduled,
    );
  }

  void _flushScheduled() {
    _debounceTimer = null;
    _firstPendingAt = null;
    unawaited(flushNow());
  }

  /// Flush perubahan ke SQLite: hapus sesi yang berhenti, upsert + append titik
  /// baru. Panggilan bersamaan diserialkan; tak pernah melempar — kegagalan
  /// dicatat dan dicoba lagi pada flush berikutnya.
  Future<void> flushNow() {
    final previous = _inFlight;
    late final Future<void> run;
    run = () async {
      if (previous != null) await previous;
      await _flushOnce();
    }()
        .whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
    _inFlight = run;
    return run;
  }

  Future<void> _flushOnce() async {
    final currentIds = manager.sessions.keys.toSet();
    final failedDeletes = <String>{};

    // Sesi yang berhenti → hapus dari DB.
    for (final id in removedIds(_knownIds, currentIds)) {
      try {
        await repo.deleteSession(id);
        _flushed.remove(id);
        _flushedVersion.remove(id);
      } catch (e, st) {
        failedDeletes.add(id); // dicoba lagi flush berikutnya
        logError('Failed to delete stopped session $id',
            tag: _tag, error: e, stack: st);
      }
    }

    // Sesi aktif → upsert + append titik baru. Gagal pada satu sesi tak
    // menghalangi sesi lain.
    for (final s in manager.activeSessions) {
      try {
        await _flushSession(s);
      } catch (e, st) {
        logError(
            'Failed to persist session "${s.project.name}" '
            '(${s.pointCount} points in memory)',
            tag: _tag,
            error: e,
            stack: st);
      }
    }

    _knownIds = {...currentIds, ...failedDeletes};
  }

  Future<void> _flushSession(TrackingSession s) async {
    await repo.upsertSession(s);
    final flushed = _flushed[s.projectId] ?? 0;
    // Snapshot panjang SEBELUM await — bila fix baru tiba saat append berjalan,
    // titik itu tak ikut ter-mark flushed (dikirim di flush berikutnya).
    final len = s.points.length;

    // Undo/clear sejak flush terakhir → posisi append basi; tulis ulang.
    final version = s.editVersion;
    if ((_flushedVersion[s.projectId] ?? 0) != version || flushed > len) {
      await repo.replacePoints(s.projectId, s.points.sublist(0, len));
      _flushed[s.projectId] = len;
      _flushedVersion[s.projectId] = version;
      return;
    }

    final pending = pendingAppendCount(len, flushed);
    if (pending > 0) {
      await repo.appendPoints(
          s.projectId, s.points.sublist(flushed, len), flushed);
      _flushed[s.projectId] = len;
    }
  }
}
