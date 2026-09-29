import 'package:flutter/foundation.dart';

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import 'tracking_session.dart';

/// Hasil percobaan memulai sesi tracking.
enum StartStatus { started, alreadyActive, capReached }

class StartResult {
  final StartStatus status;
  final TrackingSession? session;
  const StartResult(this.status, [this.session]);
  bool get ok => status == StartStatus.started;
}

/// Sumber kebenaran state tracking multi-project. Memegang banyak
/// [TrackingSession]; satu stream GPS di-fan-out ke SEMUA sesi non-paused.
///
/// Batas [maxConcurrent] disuntik (dari AppSettings, rentang 3–7). Layar & kartu
/// hanya membaca + memerintah (start/stop) — tak menyimpan state tracking sendiri
/// agar sesi tetap hidup saat pindah layar.
class TrackingSessionManager extends ChangeNotifier {
  TrackingSessionManager({int maxConcurrent = 3})
      : _maxConcurrent = maxConcurrent;

  /// Instance bersama untuk seluruh app (UI + stream GPS).
  static final TrackingSessionManager instance = TrackingSessionManager();

  final Map<String, TrackingSession> _sessions = {};
  int _maxConcurrent;

  int get maxConcurrent => _maxConcurrent;
  set maxConcurrent(int value) {
    _maxConcurrent = value;
    notifyListeners();
  }

  Map<String, TrackingSession> get sessions => Map.unmodifiable(_sessions);
  List<TrackingSession> get activeSessions => _sessions.values.toList();
  /// Semua sesi, termasuk draft pendingSave.
  int get activeCount => _sessions.length;

  /// Sesi yang sedang merekam — penentu nyala/mati feed GPS.
  int get recordingCount => _sessions.values.where((s) => s.isRecording).length;

  /// Sesi recording + paused — yang dihitung terhadap cap.
  int get liveCount => _sessions.values.where((s) => s.isLive).length;
  bool get hasActive => _sessions.isNotEmpty;

  bool isActive(String projectId) => _sessions.containsKey(projectId);
  TrackingSession? sessionFor(String projectId) => _sessions[projectId];

  /// Mulai sesi untuk [project]. Tolak bila melebihi cap (recording+paused).
  /// Sesi yang sudah ada → alreadyActive; draft pendingSave hanya boleh
  /// dilanjutkan bila masih ada slot.
  StartResult start(Project project,
      {TrackSource source = TrackSource.phone}) {
    final existing = _sessions[project.id];
    if (existing != null) {
      if (existing.pendingSave && liveCount >= _maxConcurrent) {
        return const StartResult(StartStatus.capReached);
      }
      return StartResult(StartStatus.alreadyActive, existing);
    }
    if (liveCount >= _maxConcurrent) {
      return const StartResult(StartStatus.capReached);
    }
    final s = TrackingSession(
        project: project, startedAt: DateTime.now(), source: source);
    _sessions[project.id] = s;
    notifyListeners();
    return StartResult(StartStatus.started, s);
  }

  /// Intake dari feed GPS [source]: hanya titik **recordable** yang di-fan-out,
  /// dan hanya ke sesi dengan sumber yang sama. Aman tanpa sesi (no-op).
  void ingest(GeoPoint point, {TrackSource source = TrackSource.phone}) {
    if (!point.recordable) return;
    if (_sessions.isEmpty) return;
    addPointToActiveSessions(point, source: source);
  }

  /// Sesi merekam yang memakai sumber SELAIN [source] — untuk memperingatkan
  /// user saat mengganti provider (sesi itu berhenti menerima titik).
  int recordingOnOtherSource(TrackSource source) => _sessions.values
      .where((s) => s.isRecording && s.source != source)
      .length;

  /// Fan-out satu titik GPS ke semua sesi merekam bersumber [source].
  ///
  /// Fix identik beruntun (timestamp + lat + lon sama) DILEWATI — pengaman
  /// bila satu fix terkirim dua kali.
  void addPointToActiveSessions(GeoPoint point,
      {TrackSource source = TrackSource.phone}) {
    var changed = false;
    for (final s in _sessions.values) {
      if (!s.isRecording || s.source != source) continue;
      if (_isDuplicateOfLast(s, point)) continue;
      s.points.add(point);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  static bool _isDuplicateOfLast(TrackingSession s, GeoPoint p) {
    if (s.points.isEmpty) return false;
    final last = s.points.last;
    return last.timestamp == p.timestamp &&
        last.latitude == p.latitude &&
        last.longitude == p.longitude;
  }

  void pause(String projectId) {
    final s = _sessions[projectId];
    if (s != null && s.isRecording) {
      s.state = SessionState.paused;
      notifyListeners();
    }
  }

  /// Lanjut merekam dari paused, atau melanjutkan draft pendingSave.
  void resume(String projectId) {
    final s = _sessions[projectId];
    if (s != null && !s.isRecording) {
      s.state = SessionState.recording;
      notifyListeners();
    }
  }

  /// Stop perekaman → draft menunggu disimpan/dibuang (tak lagi menahan cap
  /// maupun service). Simpan/Buang memanggil [stop] untuk melepasnya.
  void finish(String projectId) {
    final s = _sessions[projectId];
    if (s != null && !s.pendingSave) {
      s.state = SessionState.pendingSave;
      notifyListeners();
    }
  }

  /// Lepas sesi (dipakai saat stop→simpan). Mengembalikan sesi yang dilepas.
  TrackingSession? stop(String projectId) {
    final s = _sessions.remove(projectId);
    if (s != null) notifyListeners();
    return s;
  }

  double distanceOf(String projectId) =>
      _sessions[projectId]?.distanceMeters ?? 0.0;

  /// Muat sesi tersimpan (dari SQLite) ke manajer saat app start (recovery).
  void restoreSessions(List<TrackingSession> sessions) {
    for (final s in sessions) {
      _sessions[s.projectId] = s;
    }
    if (sessions.isNotEmpty) notifyListeners();
  }
}
