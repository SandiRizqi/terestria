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
  int get activeCount => _sessions.length;
  bool get hasActive => _sessions.isNotEmpty;

  bool isActive(String projectId) => _sessions.containsKey(projectId);
  TrackingSession? sessionFor(String projectId) => _sessions[projectId];

  /// Mulai sesi untuk [project]. Tolak bila sudah aktif atau melebihi cap.
  StartResult start(Project project) {
    final existing = _sessions[project.id];
    if (existing != null) {
      return StartResult(StartStatus.alreadyActive, existing);
    }
    if (_sessions.length >= _maxConcurrent) {
      return const StartResult(StartStatus.capReached);
    }
    final s = TrackingSession(project: project, startedAt: DateTime.now());
    _sessions[project.id] = s;
    notifyListeners();
    return StartResult(StartStatus.started, s);
  }

  /// Intake dari stream GPS: hanya titik **recordable** yang di-fan-out.
  /// Aman dipanggil walau tak ada sesi aktif (no-op).
  void ingest(GeoPoint point) {
    if (!point.recordable) return;
    if (_sessions.isEmpty) return;
    addPointToActiveSessions(point);
  }

  /// Fan-out satu titik GPS ke semua sesi aktif yang tidak paused.
  void addPointToActiveSessions(GeoPoint point) {
    var changed = false;
    for (final s in _sessions.values) {
      if (!s.paused) {
        s.points.add(point);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void pause(String projectId) {
    final s = _sessions[projectId];
    if (s != null && !s.paused) {
      s.paused = true;
      notifyListeners();
    }
  }

  void resume(String projectId) {
    final s = _sessions[projectId];
    if (s != null && s.paused) {
      s.paused = false;
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
}
