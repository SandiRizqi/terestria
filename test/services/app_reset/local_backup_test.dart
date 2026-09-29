import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/app_reset/local_backup_service.dart';
import 'package:geoform_app/services/tracking/tracking_session.dart';

final _t = DateTime.utc(2026, 9, 29, 3);

GeoPoint _p(double lon, double lat) =>
    GeoPoint(latitude: lat, longitude: lon, timestamp: _t);

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('backup'));
  tearDown(() async => tmp.delete(recursive: true));

  test('ZIP berisi project, record, GeoJSON, foto tertunda & sesi tracking',
      () async {
    final photo = File('${tmp.path}/IMG_1.jpg')
      ..writeAsBytesSync(List<int>.generate(2048, (i) => i % 251));
    final project = Project(
      id: 'project-0001',
      name: 'Blok A/1',
      description: '',
      geometryType: GeometryType.point,
      formFields: [
        FormFieldModel(id: 'f', label: 'Photo', type: FieldType.photo),
      ],
      createdAt: _t,
      updatedAt: _t,
    );
    final records = [
      GeoData(
        id: 'rec-1',
        projectId: project.id,
        formData: {
          'Photo': [
            {'localPath': photo.path, 'name': 'IMG_1.jpg'},
            {'localPath': '${tmp.path}/gone.jpg', 'name': 'gone.jpg'},
            {'localPath': '${tmp.path}/up.jpg', 'serverKey': 'k1'},
          ],
        },
        points: [_p(106.8, -6.2)],
        createdAt: _t,
        updatedAt: _t,
      ),
      GeoData(
        id: 'rec-2',
        projectId: project.id,
        formData: const {},
        points: const [],
        createdAt: _t,
        updatedAt: _t,
        isSynced: true,
      ),
    ];
    final lineProject = Project(
      id: 'p2',
      name: 'Jalan',
      description: '',
      geometryType: GeometryType.line,
      formFields: const [],
      createdAt: _t,
      updatedAt: _t,
    );
    final session = TrackingSession(
      project: lineProject,
      startedAt: _t,
      points: [_p(106.8, -6.2), _p(106.801, -6.2)],
      state: SessionState.paused,
    );

    final service = LocalBackupService(
      loadProjects: () async => [project],
      loadRecords: (id) async => id == project.id ? records : const [],
      trackingSessions: () => [session],
      outputDir: () async => Directory('${tmp.path}/out'),
      now: () => DateTime(2026, 9, 29, 10, 5),
    );
    final progress = <String>[];
    final result =
        await service.create(username: 'sur.veyor', onProgress: progress.add);

    expect(p(result.file.path), 'terestria_backup_sur_veyor_20260929_1005.zip');
    expect(result.projects, 1);
    expect(result.records, 2);
    expect(result.unsyncedRecords, 1);
    expect(result.photos, 1);
    expect(result.missingPhotos.single, endsWith('gone.jpg'));
    expect(result.trackingSessions, 1);
    expect(progress, isNotEmpty);

    final archive =
        ZipDecoder().decodeBytes(result.file.readAsBytesSync());
    final names = archive.files.map((f) => f.name).toSet();
    expect(
        names,
        containsAll([
          'manifest.json',
          'README.txt',
          'projects/Blok_A_1/project.json',
          'projects/Blok_A_1/records.json',
          'projects/Blok_A_1/Blok_A_1.geojson',
          'projects/Blok_A_1/photos/rec-1/IMG_1.jpg',
          'tracking_sessions.json',
          'tracking_sessions.geojson',
        ]));

    // Foto utuh (disimpan tanpa kompresi).
    final img = archive.findFile('projects/Blok_A_1/photos/rec-1/IMG_1.jpg')!;
    expect(img.content, photo.readAsBytesSync());

    final manifest = jsonDecode(
        utf8.decode(archive.findFile('manifest.json')!.content)) as Map;
    expect(manifest['totals']['unsyncedRecords'], 1);
    expect(manifest['projects'][0]['recordsWithoutGeometry'], 1);

    final records2 = jsonDecode(utf8.decode(
        archive.findFile('projects/Blok_A_1/records.json')!.content)) as List;
    expect(records2.map((r) => r['id']), ['rec-1', 'rec-2']);

    final sessions = jsonDecode(utf8.decode(
        archive.findFile('tracking_sessions.geojson')!.content)) as Map;
    expect((sessions['features'] as List).single['geometry']['type'],
        'LineString');
  });

  test('gagal membaca → berkas setengah jadi dihapus & error diteruskan',
      () async {
    final out = Directory('${tmp.path}/out');
    final service = LocalBackupService(
      loadProjects: () async => throw const FileSystemException('disk'),
      trackingSessions: () => const [],
      outputDir: () async => out,
    );
    await expectLater(service.create(), throwsA(isA<FileSystemException>()));
    expect(out.listSync(), isEmpty);
  });

  test('safeName', () {
    expect(LocalBackupService.safeName('Blok A/1'), 'Blok_A_1');
    expect(LocalBackupService.safeName('  '), 'untitled');
    expect(LocalBackupService.safeName('Kebun-2'), 'Kebun-2');
  });
}

String p(String path) => path.split(Platform.pathSeparator).last;
