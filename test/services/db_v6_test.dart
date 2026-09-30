import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/services/database_service.dart';

/// DB v6: versi server per record (`serverUpdatedAt`) untuk deteksi konflik,
/// alasan gagal push terakhir (`lastSyncError`), dan tabel `sync_conflicts`.

final _serverVersion = DateTime.parse('2026-09-30T08:00:00.123456Z');

GeoData _geo({DateTime? serverUpdatedAt, String? lastSyncError}) => GeoData(
      id: 'g1',
      projectId: 'p1',
      formData: const {'A': 1},
      points: [
        GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026, 9, 30),
      updatedAt: DateTime.utc(2026, 9, 30, 1),
      serverUpdatedAt: serverUpdatedAt,
      lastSyncError: lastSyncError,
    );

void main() {
  test('versi DB minimal 6', () {
    expect(DatabaseService.schemaVersion, greaterThanOrEqualTo(6));
  });

  group('missingColumns (migrasi v6 idempoten)', () {
    test('melaporkan kolom yang belum ada saja (tak peka kapital)', () {
      final pragma = [
        {'cid': 0, 'name': 'id'},
        {'cid': 1, 'name': 'SERVERUPDATEDAT'},
      ];
      expect(
          DatabaseService.missingColumns(
              pragma, const ['serverUpdatedAt', 'lastSyncError']),
          ['lastSyncError']);
      expect(DatabaseService.missingColumns(const [], const ['a']), ['a']);
    });
  });

  group('baris DB geo_data', () {
    test('serverUpdatedAt disimpan dalam MIKROdetik — versi dikirim balik '
        'persis sama (ms akan membuat setiap push dianggap konflik)', () {
      final row = DatabaseService.geoDataToRow(
          _geo(serverUpdatedAt: _serverVersion, lastSyncError: 'x'));
      expect(row['serverUpdatedAt'], _serverVersion.microsecondsSinceEpoch);
      expect(row['lastSyncError'], 'x');

      final back = DatabaseService.geoDataFromRow({
        ...row,
        'isSynced': 0,
      });
      expect(back.serverUpdatedAt!.isAtSameMomentAs(_serverVersion), isTrue);
      expect(back.serverUpdatedAt!.toUtc().toIso8601String(),
          '2026-09-30T08:00:00.123456Z');
      expect(back.lastSyncError, 'x');
    });

    test('baris lama (kolom v6 kosong) tetap terbaca', () {
      final row = DatabaseService.geoDataToRow(_geo())
        ..remove('serverUpdatedAt')
        ..remove('lastSyncError');
      final back = DatabaseService.geoDataFromRow(row);
      expect(back.serverUpdatedAt, isNull);
      expect(back.lastSyncError, isNull);
    });
  });

  group('GeoData model', () {
    test('JSON lokal bolak-balik mempertahankan versi server & error', () {
      final back = GeoData.fromJson(
          _geo(serverUpdatedAt: _serverVersion, lastSyncError: 'x').toJson());
      expect(back.serverUpdatedAt!.isAtSameMomentAs(_serverVersion), isTrue);
      expect(back.lastSyncError, 'x');
    });

    test('copyWith bisa mengosongkan lastSyncError', () {
      final g = _geo(lastSyncError: 'x');
      expect(g.copyWith(clearLastSyncError: true).lastSyncError, isNull);
      expect(g.copyWith().lastSyncError, 'x');
    });
  });
}
