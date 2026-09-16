import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
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

    test('ingest tanpa sesi aktif tak error', () {
      final m = TrackingSessionManager(maxConcurrent: 3);
      m.ingest(_pt(0, 0));
      expect(m.activeCount, 0);
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
}
