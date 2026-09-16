import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/services/tracking/tracking_session.dart';
import 'package:geoform_app/services/tracking/session_repository.dart';

/// Serialisasi baris SQLite untuk persistensi sesi (bagian berisiko; CRUD DB
/// diverifikasi manual karena sqflite butuh platform).
Project _proj(String id, GeometryType t) => Project(
      id: id,
      name: 'P$id',
      description: '',
      geometryType: t,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('sessionRow ↔ sessionFromRow round-trip', () {
    final started = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final s = TrackingSession(
      project: _proj('a', GeometryType.polygon),
      startedAt: started,
      paused: true,
    );
    final row = SessionRepository.sessionRow(s);
    expect(row['projectId'], 'a');
    expect(row['startedAt'], 1700000000000);
    expect(row['paused'], 1);

    final back = SessionRepository.sessionFromRow(row, [
      GeoPoint(latitude: 0, longitude: 0, timestamp: started),
    ]);
    expect(back.projectId, 'a');
    expect(back.project.geometryType, GeometryType.polygon);
    expect(back.startedAt.millisecondsSinceEpoch, 1700000000000);
    expect(back.paused, isTrue);
    expect(back.points.length, 1);
  });

  test('pointRow ↔ pointFromRow round-trip', () {
    final p = GeoPoint(
      latitude: 1.5,
      longitude: 2.5,
      altitude: 10,
      accuracy: 5,
      speed: 3,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    final row = SessionRepository.pointRow('a', 7, p);
    expect(row['projectId'], 'a');
    expect(row['seq'], 7);

    final back = SessionRepository.pointFromRow(row);
    expect(back.latitude, 1.5);
    expect(back.longitude, 2.5);
  });
}
