import 'package:flutter/foundation.dart';

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../../utils/app_logger.dart';
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

  static const _tag = 'SESSION';

  void _logCapReached(Project project) => logWarn(
      'Start "${project.name}" ditolak: batas $_maxConcurrent project '
      '(merekam+jeda) tercapai',
      tag: _tag);

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
        _logCapReached(project);
        return const StartResult(StartStatus.capReached);
      }
      return StartResult(StartStatus.alreadyActive, existing);
    }
    if (liveCount >= _maxConcurrent) {
      _logCapReached(project);
      return const StartResult(StartStatus.capReached);
    }
    final s = TrackingSession(
        project: project, startedAt: DateTime.now(), source: source);
    _sessions[project.id] = s;
    logInfo('Start "${project.name}" (${project.id}, sumber=${source.name}, '
        '${project.geometryType.name})', tag: _tag);
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
      logInfo('Jeda "${s.project.name}" (${s.pointCount} titik)', tag: _tag);
      notifyListeners();
    }
  }

  /// Lanjut merekam dari paused, atau melanjutkan draft pendingSave.
  void resume(String projectId) {
    final s = _sessions[projectId];
    if (s != null && !s.isRecording) {
      final from = s.pendingSave ? ' (dari draft)' : '';
      s.state = SessionState.recording;
      logInfo('Lanjut "${s.project.name}"$from', tag: _tag);
      notifyListeners();
    }
  }

  /// Titik manual (tambah-titik-tengah / tap peta) — aksi user, jadi diterima
  /// apa pun status sesinya.
  void appendManual(String projectId, GeoPoint point) {
    final s = _sessions[projectId];
    if (s == null) return;
    s.points.add(point);
    notifyListeners();
  }

  /// Undo titik terakhir sesi.
  void removeLast(String projectId) {
    final s = _sessions[projectId];
    if (s == null || s.points.isEmpty) return;
    s.points.removeLast();
    s.editVersion++;
    logDebug('Undo titik "${s.project.name}" → ${s.pointCount}', tag: _tag);
    notifyListeners();
  }

  /// Hapus semua titik sesi (sesi tetap ada).
  void clearPoints(String projectId) {
    final s = _sessions[projectId];
    if (s == null || s.points.isEmpty) return;
    logInfo('Hapus semua titik "${s.project.name}" (${s.pointCount})',
        tag: _tag);
    s.points.clear();
    s.editVersion++;
    notifyListeners();
  }

  /// Ganti seluruh titik sesi (Undo setelah "Clear"). Persistensi menulis
  /// ulang titik karena [TrackingSession.editVersion] naik.
  void replacePoints(String projectId, List<GeoPoint> points) {
    final s = _sessions[projectId];
    if (s == null) return;
    s.points
      ..clear()
      ..addAll(points);
    s.editVersion++;
    logInfo('Pulihkan ${points.length} titik "${s.project.name}" (undo clear)',
        tag: _tag);
    notifyListeners();
  }

  /// Stop perekaman → draft menunggu disimpan/dibuang (tak lagi menahan cap
  /// maupun service). Simpan/Buang memanggil [stop] untuk melepasnya.
  void finish(String projectId) {
    final s = _sessions[projectId];
    if (s != null && !s.pendingSave) {
      s.state = SessionState.pendingSave;
      logInfo('Stop "${s.project.name}" → draft (${s.pointCount} titik)',
          tag: _tag);
      notifyListeners();
    }
  }

  /// Lepas sesi (dipakai saat stop→simpan). Mengembalikan sesi yang dilepas.
  TrackingSession? stop(String projectId) {
    final s = _sessions.remove(projectId);
    if (s != null) {
      logInfo('Lepas "${s.project.name}" (${s.pointCount} titik)', tag: _tag);
      notifyListeners();
    }
    return s;
  }

  /// Buang SEMUA sesi tanpa menyimpan (reset app saat logout).
  void clearAll() {
    if (_sessions.isEmpty) return;
    logInfo('Buang ${_sessions.length} sesi (reset app)', tag: _tag);
    _sessions.clear();
    notifyListeners();
  }

  double distanceOf(String projectId) =>
      _sessions[projectId]?.distanceMeters ?? 0.0;

  /// Muat sesi tersimpan (dari SQLite) ke manajer saat app start (recovery).
  void restoreSessions(List<TrackingSession> sessions) {
    for (final s in sessions) {
      _sessions[s.projectId] = s;
    }
    if (sessions.isNotEmpty) {
      logInfo(
          'Pulihkan ${sessions.length} sesi: ${sessions.map((s) => '"${s.project.name}" ${s.state.name} ${s.pointCount} titik').join(', ')}',
          tag: _tag);
      notifyListeners();
    }
  }
}
