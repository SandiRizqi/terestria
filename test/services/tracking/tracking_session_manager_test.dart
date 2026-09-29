import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/services/tracking/tracking_session.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';

/// Manajer multi-sesi tracking: start (cap + no-dup), fan-out titik ke sesi
/// non-paused, pause/resume, stop, activeCount/isActive/distanceOf.
Project _proj(String id, {GeometryType type = GeometryType.line}) => Project(
      id: id,
      name: 'P$id',
      description: '',
      geometryType: type,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

GeoPoint _pt(double lat, double lon) =>
    GeoPoint(latitude: lat, longitude: lon, timestamp: DateTime(2026, 1, 1));

void main() {
  group('TrackingSessionManager', () {
    test('start mendaftarkan sesi & isActive/activeCount benar', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      final r = m.start(_proj('a'));
      expect(r.status, StartStatus.started);
      expect(m.isActive('a'), isTrue);
      expect(m.activeCount, 1);
    });

    test('start dua kali project sama → alreadyActive (no-dup)', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      final r = m.start(_proj('a'));
      expect(r.status, StartStatus.alreadyActive);
      expect(m.activeCount, 1);
    });

    test('start melebihi cap → capReached', () {
      final m = TrackingSessionManager(maxConcurrent: 2);
      m.start(_proj('a'));
      m.start(_proj('b'));
      final r = m.start(_proj('c'));
      expect(r.status, StartStatus.capReached);
      expect(m.activeCount, 2);
      expect(m.isActive('c'), isFalse);
    });

    test('addPointToActiveSessions fan-out ke SEMUA sesi aktif', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.start(_proj('b'));
      m.addPointToActiveSessions(_pt(0, 0));
      m.addPointToActiveSessions(_pt(0, 1));
      expect(m.sessionFor('a')!.points.length, 2);
      expect(m.sessionFor('b')!.points.length, 2);
    });

    test('sesi paused TIDAK menerima titik', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.start(_proj('b'));
      m.pause('b');
      m.addPointToActiveSessions(_pt(0, 0));
      expect(m.sessionFor('a')!.points.length, 1);
      expect(m.sessionFor('b')!.points.length, 0);
      m.resume('b');
      m.addPointToActiveSessions(_pt(0, 1));
      expect(m.sessionFor('b')!.points.length, 1);
    });

    test('stop melepas sesi & mengembalikannya', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.addPointToActiveSessions(_pt(0, 0));
      final s = m.stop('a');
      expect(s, isNotNull);
      expect(s!.points.length, 1);
      expect(m.isActive('a'), isFalse);
      expect(m.activeCount, 0);
    });

    test('distanceOf naik saat titik bertambah', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.addPointToActiveSessions(_pt(0, 0));
      final d0 = m.distanceOf('a');
      m.addPointToActiveSessions(_pt(0, 0.01));
      expect(m.distanceOf('a'), greaterThan(d0));
    });

    test('ingest hanya menerima titik recordable', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.ingest(GeoPoint(
          latitude: 0,
          longitude: 0,
          timestamp: DateTime(2026, 1, 1),
          recordable: false));
      expect(m.sessionFor('a')!.points.length, 0);
      m.ingest(GeoPoint(
          latitude: 0,
          longitude: 0,
          timestamp: DateTime(2026, 1, 1),
          recordable: true));
      expect(m.sessionFor('a')!.points.length, 1);
    });

    test('fan-out dedup fix identik beruntun (aman dari double-call)', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      final p = GeoPoint(
          latitude: 1, longitude: 2, timestamp: DateTime(2026, 1, 1, 10, 0, 0));
      m.addPointToActiveSessions(p);
      m.addPointToActiveSessions(p); // fix sama (double) → dilewati
      expect(m.sessionFor('a')!.points.length, 1);
      // koordinat sama tapi timestamp beda (diam sungguhan) → tetap ditambah
      m.addPointToActiveSessions(GeoPoint(
          latitude: 1, longitude: 2, timestamp: DateTime(2026, 1, 1, 10, 0, 1)));
      expect(m.sessionFor('a')!.points.length, 2);
    });

    test('ingest tanpa sesi aktif tak error', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.ingest(_pt(0, 0));
      expect(m.activeCount, 0);
    });

    test('restoreSessions memuat sesi tersimpan', () {
      final m = TrackingSessionManager(maxConcurrent: 5);
      final s = TrackingSession(
        project: _proj('a'),
        startedAt: DateTime(2026, 1, 1),
        points: [_pt(0, 0), _pt(0, 1)],
      );
      m.restoreSessions([s]);
      expect(m.isActive('a'), isTrue);
      expect(m.sessionFor('a')!.points.length, 2);
    });

    test('recordingCount = sesi yang tidak di-pause', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.start(_proj('b'));
      expect(m.recordingCount, 2);
      m.pause('a');
      expect(m.recordingCount, 1);
      expect(m.activeCount, 2);
    });

    test('finish → pendingSave: berhenti menerima titik, sesi tetap ada', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.addPointToActiveSessions(_pt(0, 0));
      m.finish('a');
      m.addPointToActiveSessions(_pt(0, 1));
      final s = m.sessionFor('a')!;
      expect(s.state, SessionState.pendingSave);
      expect(s.points.length, 1);
      expect(m.recordingCount, 0);
    });

    test('pendingSave tidak dihitung cap → Start project baru tetap boleh', () {
      final m = TrackingSessionManager(maxConcurrent: 2);
      m.start(_proj('a'));
      m.start(_proj('b'));
      m.finish('a'); // A menunggu disimpan
      expect(m.start(_proj('c')).status, StartStatus.started);
      expect(m.liveCount, 2); // b + c
      expect(m.activeCount, 3); // termasuk draft a
    });

    test('paused tetap dihitung cap', () {
      final m = TrackingSessionManager(maxConcurrent: 2);
      m.start(_proj('a'));
      m.start(_proj('b'));
      m.pause('a');
      expect(m.start(_proj('c')).status, StartStatus.capReached);
    });

    test('Start ulang draft pendingSave saat cap penuh → capReached', () {
      final m = TrackingSessionManager(maxConcurrent: 2);
      m.start(_proj('a'));
      m.finish('a');
      m.start(_proj('b'));
      m.start(_proj('c'));
      expect(m.start(_proj('a')).status, StartStatus.capReached);
    });

    test('resume dari pendingSave → merekam lagi (lanjutkan draft)', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.finish('a');
      expect(m.start(_proj('a')).status, StartStatus.alreadyActive);
      m.resume('a');
      expect(m.sessionFor('a')!.state, SessionState.recording);
    });

    test('pause tak berlaku pada draft pendingSave', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.finish('a');
      m.pause('a');
      expect(m.sessionFor('a')!.state, SessionState.pendingSave);
    });

    test('titik hanya masuk ke sesi dengan sumber GPS yang sama', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('hp'));
      m.start(_proj('rtk'), source: TrackSource.emlid);

      m.ingest(_pt(0, 0)); // default: phone
      m.ingest(_pt(0, 1), source: TrackSource.emlid);
      m.ingest(_pt(0, 2), source: TrackSource.emlid);

      expect(m.sessionFor('hp')!.points.length, 1);
      expect(m.sessionFor('rtk')!.points.length, 2);
      expect(m.sessionFor('rtk')!.source, TrackSource.emlid);
    });

    test('recordingOnOtherSource menghitung sesi merekam di sumber lain', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.start(_proj('b'), source: TrackSource.emlid);
      m.start(_proj('c'), source: TrackSource.emlid);
      m.pause('c');
      expect(m.recordingOnOtherSource(TrackSource.phone), 1); // b
      expect(m.recordingOnOtherSource(TrackSource.emlid), 1); // a
    });

    test('appendManual menambah titik manual walau sesi tidak merekam', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.finish('a'); // draft
      m.appendManual('a', _pt(0, 0));
      expect(m.sessionFor('a')!.points.length, 1);
    });

    test('removeLast & clearPoints mengubah titik + menaikkan editVersion', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.start(_proj('a'));
      m.addPointToActiveSessions(_pt(0, 0));
      m.addPointToActiveSessions(_pt(0, 1));
      var n = 0;
      m.addListener(() => n++);

      m.removeLast('a');
      expect(m.sessionFor('a')!.points.length, 1);
      expect(m.sessionFor('a')!.editVersion, 1);

      m.clearPoints('a');
      expect(m.sessionFor('a')!.points, isEmpty);
      expect(m.sessionFor('a')!.editVersion, 2);
      expect(n, 2);

      m.removeLast('a'); // kosong → no-op
      expect(m.sessionFor('a')!.editVersion, 2);
    });

    test('notifyListeners terpanggil saat start & addPoint', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      var n = 0;
      m.addListener(() => n++);
      m.start(_proj('a'));
      m.addPointToActiveSessions(_pt(0, 0));
      expect(n, greaterThanOrEqualTo(2));
    });
  });

  test('clearAll membuang semua sesi (reset logout) + memberi tahu listener',
      () {
    final m = TrackingSessionManager(maxConcurrent: 3);
    m.start(_proj('a'));
    m.start(_proj('b'));
    m.pause('b');
    var n = 0;
    m.addListener(() => n++);

    m.clearAll();

    expect(m.activeCount, 0);
    expect(m.recordingCount, 0);
    expect(n, 1);
    m.clearAll(); // sudah kosong → tak memberi tahu lagi
    expect(n, 1);
  });
}
