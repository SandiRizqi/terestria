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
  List<TrackingSession> stored = [];
  void Function()? onAppend;
  @override
  Future<void> upsertSession(TrackingSession s) async {}
  @override
  Future<void> deleteSession(String id) async {}
  @override
  Future<List<TrackingSession>> restoreAll() async => stored;
  @override
  Future<void> appendPoints(String id, List<GeoPoint> pts, int fromSeq) async {
    appended.addAll(pts);
    onAppend?.call();
  }

  /// Isi DB setelah replace (tulis ulang penuh).
  List<GeoPoint>? replaced;
  @override
  Future<void> replacePoints(String id, List<GeoPoint> pts) async {
    replaced = List.of(pts);
    appended
      ..clear()
      ..addAll(pts);
  }
}

/// Helper murni untuk persistensi & notifikasi multi-sesi (koordinator penuh
/// butuh DB/plugin → diverifikasi manual).
void main() {
  group('trackingNotificationText', () {
    test('tak ada yang merekam → null (service mati, tak ada notifikasi)', () {
      expect(trackingNotificationText(recording: 0, pending: 2), isNull);
    });
    test('hanya merekam', () {
      expect(trackingNotificationText(recording: 1), 'Merekam 1 project');
    });
    test('ringkasan per status', () {
      expect(trackingNotificationText(recording: 2, paused: 1, pending: 1),
          'Merekam 2 project · 1 jeda · 1 belum disimpan');
    });
  });

  group('providerSwitchWarningText', () {
    test('tak ada sesi di sumber lain → null (tak perlu konfirmasi)', () {
      expect(providerSwitchWarningText(0), isNull);
    });
    test('ada sesi terdampak → teks menyebut jumlahnya', () {
      expect(providerSwitchWarningText(2), contains('2 project'));
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

  test('undo lalu titik baru → DB ditulis ulang, bukan append basi', () async {
    final mgr = TrackingSessionManager(maxConcurrent: 3);
    final repo = _FakeRepo();
    final coord = TrackingPersistenceCoordinator(
        manager: mgr, repo: repo);
    mgr.start(_proj('u'));
    mgr.addPointToActiveSessions(_pt(0));
    mgr.addPointToActiveSessions(_pt(1));
    await coord.flushNow();
    expect(repo.appended.length, 2);

    mgr.removeLast('u'); // undo titik ke-2
    mgr.addPointToActiveSessions(_pt(5)); // panjang kembali 2, isi berbeda
    await coord.flushNow();

    expect(repo.replaced?.map((p) => p.longitude), [0, 5]);
    expect(repo.appended.map((p) => p.longitude), [0, 5]);

    mgr.addPointToActiveSessions(_pt(6)); // setelah replace → append normal
    await coord.flushNow();
    expect(repo.appended.map((p) => p.longitude), [0, 5, 6]);
    mgr.stop('u');
  });

  test('restore memuat sesi sebagai PAUSED (feed GPS tak menyala sendiri)',
      () async {
    final mgr = TrackingSessionManager(maxConcurrent: 3);
    final repo = _FakeRepo()
      ..stored = [
        TrackingSession(
            project: _proj('a'),
            startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
            points: [_pt(0), _pt(1)]),
      ];
    final coord = TrackingPersistenceCoordinator(
        manager: mgr, repo: repo);

    await coord.restore();

    final s = mgr.sessionFor('a')!;
    expect(s.paused, isTrue);
    expect(s.points.length, 2);
    expect(mgr.recordingCount, 0); // engine tak menyalakan service saat launch
    mgr.stop('a');
  });
}
