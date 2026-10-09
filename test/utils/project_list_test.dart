import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/utils/project_list.dart';

/// Daftar project (template "Projects list"): ringkasan data lokal per
/// project, filter All / Unsynced / From server, tag status, dan subjudul.

Project _p(
  String id, {
  String name = 'Blok',
  String description = '',
  String? createdBy = 'rizky',
  bool synced = true,
  DateTime? updatedAt,
}) =>
    Project(
      id: id,
      name: name,
      description: description,
      geometryType: GeometryType.polygon,
      formFields: const [],
      createdAt: DateTime(2026),
      updatedAt: updatedAt ?? DateTime(2026, 10, 1),
      isSynced: synced,
      createdBy: createdBy,
    );

const _none = ProjectDataStats.empty;

void main() {
  group('projectDataStatsFromRows', () {
    test('baris query terkelompok → ringkasan per project', () {
      final stats = projectDataStatsFromRows([
        {
          'projectId': 'a',
          'total': 248,
          'unsynced': 12,
          'failed': 0,
          'lastUpdated': DateTime(2026, 10, 9, 12).millisecondsSinceEpoch,
        },
        {'projectId': 'b', 'total': 3, 'unsynced': null, 'failed': null, 'lastUpdated': null},
      ]);
      expect(stats['a']!.total, 248);
      expect(stats['a']!.unsynced, 12);
      expect(stats['a']!.lastUpdated, DateTime(2026, 10, 9, 12));
      expect((stats['b']!.unsynced, stats['b']!.failed, stats['b']!.lastUpdated),
          (0, 0, null));
    });
  });

  group('isFromServer', () {
    test('dibuat user lain → dari server; milik sendiri/tanpa pembuat → bukan', () {
      expect(isFromServer(_p('a', createdBy: 'dewi.s'), 'rizky'), isTrue);
      expect(isFromServer(_p('a', createdBy: ' Rizky '), 'rizky'), isFalse);
      expect(isFromServer(_p('a', createdBy: null), 'rizky'), isFalse);
      expect(isFromServer(_p('a', createdBy: 'dewi.s'), null), isFalse);
    });
  });

  group('filterProjects', () {
    final projects = [
      _p('a', name: 'Palm Estate · Block C'),
      _p('b', name: 'River Buffer', createdBy: 'dewi.s'),
      _p('c', name: 'Well Inventory', synced: false),
      _p('d', name: 'Forest Plot', description: 'sensus pohon'),
    ];
    final stats = {
      'a': const ProjectDataStats(total: 248, unsynced: 12, failed: 0),
    };

    List<String> ids(ProjectListFilter f, [String q = '']) => filterProjects(
          projects,
          query: q,
          filter: f,
          stats: stats,
          currentUsername: 'rizky',
        ).map((p) => p.id).toList();

    test('All = semua', () => expect(ids(ProjectListFilter.all), ['a', 'b', 'c', 'd']));
    test('Unsynced = record belum ter-upload atau project belum di server',
        () => expect(ids(ProjectListFilter.unsynced), ['a', 'c']));
    test('From server = dibuat user lain',
        () => expect(ids(ProjectListFilter.fromServer), ['b']));
    test('cari nama/deskripsi/pembuat, digabung dengan filter', () {
      expect(ids(ProjectListFilter.all, 'pohon'), ['d']);
      expect(ids(ProjectListFilter.all, 'DEWI'), ['b']);
      expect(ids(ProjectListFilter.unsynced, 'well'), ['c']);
    });
  });

  group('projectSyncTag', () {
    test('gagal > belum ter-upload > project lokal > tersinkron', () {
      expect(
          projectSyncTag(_p('a'), const ProjectDataStats(total: 5, unsynced: 3, failed: 1)),
          ('Sync failed', TagTone.danger));
      expect(
          projectSyncTag(_p('a'), const ProjectDataStats(total: 5, unsynced: 12, failed: 0)),
          ('12 unsynced', TagTone.warning));
      expect(projectSyncTag(_p('a', synced: false), _none), ('Local', TagTone.warning));
      expect(projectSyncTag(_p('a'), _none), ('Synced', TagTone.success));
    });
  });

  group('projectSubtitle', () {
    final now = DateTime(2026, 10, 9, 14, 30);
    test('jumlah record · aktivitas terakhir (project atau record terbaru)', () {
      expect(
        projectSubtitle(
          _p('a', updatedAt: DateTime(2026, 10, 1)),
          ProjectDataStats(
              total: 248, unsynced: 0, failed: 0, lastUpdated: DateTime(2026, 10, 9, 12, 20)),
          now,
        ),
        '248 records · 2 h ago',
      );
    });
    test('satu record; tanpa record → waktu ubah project', () {
      expect(
        projectSubtitle(_p('a', updatedAt: DateTime(2026, 10, 8, 9)),
            const ProjectDataStats(total: 1, unsynced: 0, failed: 0), now),
        '1 record · yesterday',
      );
      expect(projectSubtitle(_p('a', updatedAt: DateTime(2026, 10, 4)), _none, now),
          '0 records · 5 d ago');
    });
  });
}
