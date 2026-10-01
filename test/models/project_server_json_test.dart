import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';

/// Project yang ditarik dari server tersimpan sebagai SUDAH sinkron. Server
/// tidak mengirim `isSynced`; dulu setiap project hasil tarik dianggap belum
/// sync lalu di-push balik oleh semua HP — termasuk HP collector (bukan
/// pembuat) — dan bisa menimpa perubahan form yang lebih baru di server.

// Bentuk respons ProjectSerializer (gis-backend) untuk satu project.
Map<String, dynamic> _serverJson() => {
      'id': 'P1',
      'name': 'Blok A',
      'description': 'Sensus TPH',
      'geometryType': 'point',
      'formFields': [
        {'id': 'f1', 'label': 'WERKS', 'type': 'text', 'required': true},
      ],
      'createdBy': 'owner',
      'collectors': ['owner', 'budi'],
      'createdAt': '2026-09-01T02:00:00Z',
      'updatedAt': '2026-09-30T02:00:00Z',
      'geoDataCount': 12,
      'bbox': null,
      'valid': null,
      'errors': [],
    };

void main() {
  test('fromServerJson: ditandai sudah sync, field lain sama dengan fromJson',
      () {
    final now = DateTime.utc(2026, 10, 1, 8);
    final fromServer = Project.fromServerJson(_serverJson(), now: now);
    final plain = Project.fromJson(_serverJson());

    expect(fromServer.isSynced, isTrue);
    expect(fromServer.syncedAt!.toUtc(), now); // dibaca sebagai waktu lokal
    expect(fromServer.toJson()..remove('isSynced')..remove('syncedAt'),
        plain.toJson()..remove('isSynced')..remove('syncedAt'));
    expect(fromServer.geoDataCount, 12);
    expect(fromServer.createdBy, 'owner');
  });

  test('fromJson tanpa isSynced tetap belum sync (JSON lokal/backup)', () {
    expect(Project.fromJson(_serverJson()).isSynced, isFalse);
  });
}
