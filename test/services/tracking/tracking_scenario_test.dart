import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/tracking/session_repository.dart';
import 'package:geoform_app/services/tracking/tracking_engine.dart';
import 'package:geoform_app/services/tracking/tracking_persistence_coordinator.dart';
import 'package:geoform_app/services/tracking/tracking_session.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';

/// Skenario end-to-end multi-project TANPA layar collection — mengunci
/// regresi bug "titik tak terekam setelah keluar layar" (heartbeat milik layar)
/// dan alur Stop → draft → restore.

Project _proj(String id) => Project(
      id: id,
      name: 'P$id',
      description: '',
      geometryType: GeometryType.line,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

class _NoopTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => true;
  @override
  int get tick => 0;
}

/// Repo in-memory yang memakai serialisasi baris ASLI SessionRepository.
class _MemoryRepo extends SessionRepository {
  final Map<String, Map<String, Object?>> rows = {};
  final Map<String, List<Map<String, Object?>>> points = {};

  @override
  Future<void> upsertSession(TrackingSession s) async =>
      rows[s.projectId] = SessionRepository.sessionRow(s);

  @override
  Future<void> appendPoints(String id, List<GeoPoint> pts, int fromSeq) async {
    final list = points.putIfAbsent(id, () => []);
    for (var i = 0; i < pts.length; i++) {
      list.add(SessionRepository.pointRow(id, fromSeq + i, pts[i]));
    }
  }

  @override
  Future<void> replacePoints(String id, List<GeoPoint> pts) async {
    points[id] = [
      for (var i = 0; i < pts.length; i++) SessionRepository.pointRow(id, i, pts[i])
    ];
  }

  @override
  Future<void> deleteSession(String id) async {
    rows.remove(id);
    points.remove(id);
  }

  @override
  Future<List<TrackingSession>> restoreAll() async => [
        for (final e in rows.entries)
          SessionRepository.sessionFromRow(e.value, [
            for (final r in points[e.key] ?? const <Map<String, Object?>>[])
              SessionRepository.pointFromRow(r)
          ]),
      ];
}

void main() {
  test('A & B merekam tanpa layar; Stop A tak mengganggu B; restore aman',
      () async {
    final mgr = TrackingSessionManager(maxConcurrent: 3);
    final phone = StreamController<GeoPoint>.broadcast();
    var running = false, starts = 0, stops = 0, heartbeats = 0;
    final engine = TrackingEngine(
      manager: mgr,
      startService: () async {
        starts++;
        return running = true;
      },
      stopService: () async {
        stops++;
        running = false;
      },
      sendHeartbeat: () => heartbeats++,
      isServiceRunning: () => running,
      periodicTimer: (_, __) => _NoopTimer(),
      phoneFeed: phone.stream,
    )..attach();
    final repo = _MemoryRepo();
    final persist = TrackingPersistenceCoordinator(manager: mgr, repo: repo);

    var sec = 0;
    Future<void> gpsFix() async {
      phone.add(GeoPoint(
          latitude: -6.2,
          longitude: 106.8 + sec * 1e-4,
          timestamp: DateTime(2026, 1, 1, 8, 0, sec++)));
      await Future<void>.delayed(Duration.zero);
    }

    // 1. Start A dari layar project A, lalu user kembali ke daftar project:
    //    TAK ADA layar collection terbuka. 20 detik berlalu (4 detak engine).
    mgr.start(_proj('A'));
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 4; i++) {
      engine.tick();
      await gpsFix();
    }
    expect(heartbeats, greaterThanOrEqualTo(4),
        reason: 'heartbeat harus datang dari engine, bukan layar');
    expect(running, isTrue);
    expect(mgr.sessionFor('A')!.points.length, 4);

    // 2. Start B → titik yang sama masuk ke A dan B; service tak di-start ulang.
    mgr.start(_proj('B'));
    await gpsFix();
    await gpsFix();
    expect(mgr.sessionFor('A')!.points.length, 6);
    expect(mgr.sessionFor('B')!.points.length, 2);
    expect(starts, 1);

    // 3. Stop A → draft; A berhenti bertambah, B lanjut, service tetap hidup.
    mgr.finish('A');
    await gpsFix();
    expect(mgr.sessionFor('A')!.points.length, 6);
    expect(mgr.sessionFor('B')!.points.length, 3);
    expect(stops, 0);

    // 4. Jeda B → tak ada yang merekam → service berhenti.
    mgr.pause('B');
    await Future<void>.delayed(Duration.zero);
    expect(stops, 1);
    expect(running, isFalse);

    // 5. App di-kill: data sudah di SQLite → dipulihkan tanpa merekam diam-diam.
    await persist.flushNow();
    final restored = TrackingSessionManager(maxConcurrent: 3);
    await TrackingPersistenceCoordinator(manager: restored, repo: repo)
        .restore();
    expect(restored.sessionFor('A')!.state, SessionState.pendingSave);
    expect(restored.sessionFor('A')!.points.length, 6);
    expect(restored.sessionFor('B')!.state, SessionState.paused);
    expect(restored.sessionFor('B')!.points.length, 3);
    expect(restored.recordingCount, 0);

    engine.detach();
    await phone.close();
  });
}
