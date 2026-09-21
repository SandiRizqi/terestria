import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/services/tracking/tracking_notification.dart';
import 'package:geoform_app/services/tracking/tracking_persistence_coordinator.dart';
import 'package:geoform_app/services/tracking/tracking_session.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';
import 'package:geoform_app/services/tracking/session_repository.dart';

Project _proj(String id) => Project(
      id: id,
      name: 'P$id',
      description: '',
      geometryType: GeometryType.line,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

GeoPoint _pt(double lon) =>
    GeoPoint(latitude: 0, longitude: lon, timestamp: DateTime(2026, 1, 1));

/// Repo palsu: catat titik yang di-append; hook onAppend mensimulasikan fix baru
/// tiba saat proses append sedang berjalan (uji race deterministik).
class _FakeRepo extends SessionRepository {
  final List<GeoPoint> appended = [];
  void Function()? onAppend;
  @override
  Future<void> upsertSession(TrackingSession s) async {}
  @override
  Future<void> deleteSession(String id) async {}
  @override
  Future<List<TrackingSession>> restoreAll() async => [];
  @override
  Future<void> appendPoints(String id, List<GeoPoint> pts, int fromSeq) async {
    appended.addAll(pts);
    onAppend?.call();
  }
}

/// Helper murni untuk persistensi & notifikasi multi-sesi (koordinator penuh
/// butuh DB/plugin → diverifikasi manual).
void main() {
  group('trackingNotificationText', () {
    test('0 sesi → null', () => expect(trackingNotificationText(0), isNull));
    test('1 sesi', () {
      expect(trackingNotificationText(1), 'Tracking 1 project aktif');
    });
    test('banyak sesi', () {
      expect(trackingNotificationText(3), 'Tracking 3 project aktif');
    });
  });

  group('pendingAppendCount', () {
    test('titik baru sejak flush', () {
      expect(pendingAppendCount(5, 3), 2);
      expect(pendingAppendCount(3, 3), 0);
      expect(pendingAppendCount(2, 5), 0); // tak pernah negatif
    });
  });

  group('removedIds', () {
    test('sesi yang berhenti terdeteksi', () {
      expect(removedIds({'a', 'b'}, {'a'}), {'b'});
      expect(removedIds({'a'}, {'a', 'b'}), <String>{});
      expect(removedIds({'a', 'b'}, {'a', 'b'}), <String>{});
    });
  });

  group('partitionRestorable', () {
    TrackingSession s(String id, DateTime started) => TrackingSession(
        project: _proj(id), startedAt: started, points: [_pt(0)]);
    final now = DateTime(2026, 1, 2, 12, 0);
    const maxAge = Duration(hours: 12);

    test('buang sesi lebih tua dari maxAge (abandoned)', () {
      final r = partitionRestorable([
        s('old', now.subtract(const Duration(hours: 20))),
        s('fresh', now.subtract(const Duration(hours: 1))),
      ], 3, now, maxAge);
      expect(r.keep.map((e) => e.projectId), ['fresh']);
      expect(r.drop.map((e) => e.projectId), ['old']);
    });

    test('batasi ke cap, simpan yang terbaru', () {
      final r = partitionRestorable([
        s('c', now.subtract(const Duration(hours: 3))),
        s('a', now.subtract(const Duration(hours: 1))),
        s('b', now.subtract(const Duration(hours: 2))),
      ], 2, now, maxAge);
      expect(r.keep.map((e) => e.projectId).toSet(), {'a', 'b'});
      expect(r.drop.map((e) => e.projectId), ['c']);
    });

    test('semua fresh & dalam cap → keep semua', () {
      final r = partitionRestorable(
          [s('a', now), s('b', now)], 3, now, maxAge);
      expect(r.keep.length, 2);
      expect(r.drop, isEmpty);
    });

    test('sesi kosong (0 titik) dibuang', () {
      final empty = TrackingSession(project: _proj('e'), startedAt: now);
      final r = partitionRestorable([empty, s('a', now)], 3, now, maxAge);
      expect(r.keep.map((e) => e.projectId), ['a']);
      expect(r.drop.map((e) => e.projectId), ['e']);
    });
  });

  test('flushNow tak kehilangan titik yang tiba saat append (race)', () async {
    final mgr = TrackingSessionManager(maxConcurrent: 3);
    mgr.stop('a');
    final repo = _FakeRepo();
    final coord = TrackingPersistenceCoordinator(manager: mgr, repo: repo);
    mgr.start(_proj('a'));
    mgr.addPointToActiveSessions(_pt(0)); // 1 titik

    // Titik ke-2 tiba TEPAT saat append titik ke-1 sedang berjalan.
    repo.onAppend = () {
      repo.onAppend = null;
      mgr.addPointToActiveSessions(_pt(1));
    };
    await coord.flushNow(); // flush pertama: hanya titik ke-1 (len ter-snapshot)
    expect(repo.appended.length, 1);

    await coord.flushNow(); // flush kedua: HARUS menambah titik ke-2 (tak hilang)
    expect(repo.appended.length, 2);

    mgr.stop('a');
  });

  test('service dihentikan HANYA saat sesi terakhir berhenti (activeCount→0)',
      () {
    final mgr = TrackingSessionManager(maxConcurrent: 3);
    mgr.stop('a');
    mgr.stop('b');
    var stops = 0;
    final coord = TrackingPersistenceCoordinator(
      manager: mgr,
      repo: _FakeRepo(),
      onAllSessionsStopped: () => stops++,
    );

    mgr.start(_proj('a'));
    coord.maybeManageService(); // 1 → service jalan
    mgr.start(_proj('b'));
    coord.maybeManageService(); // 2 → tetap jalan
    expect(stops, 0);

    mgr.stop('a');
    coord.maybeManageService(); // 1 → masih ada B → jangan stop
    expect(stops, 0);

    mgr.stop('b');
    coord.maybeManageService(); // 0 → stop service
    coord.maybeManageService(); // tetap 0 → tak dobel
    expect(stops, 1);
  });

  test('notifikasi hanya di-update saat activeCount berubah (bukan tiap fix)',
      () {
    final mgr = TrackingSessionManager(maxConcurrent: 3);
    mgr.stop('a');
    mgr.stop('b');
    var calls = 0;
    final coord = TrackingPersistenceCoordinator(
        manager: mgr, repo: _FakeRepo(), notify: (_) => calls++);

    mgr.start(_proj('a'));
    coord.maybeUpdateNotification(); // 1 → update
    mgr.addPointToActiveSessions(_pt(0));
    coord.maybeUpdateNotification(); // masih 1 → TIDAK update
    mgr.addPointToActiveSessions(_pt(1));
    coord.maybeUpdateNotification(); // masih 1 → TIDAK update
    mgr.start(_proj('b'));
    coord.maybeUpdateNotification(); // 2 → update
    expect(calls, 2);

    mgr.stop('a');
    mgr.stop('b');
  });
}
