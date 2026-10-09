import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/utils/local_delete.dart';

/// Hapus data project dari HP saja: hitungan untuk dialog peringatan dan
/// record yang dihapus oleh "Clear local data".

GeoData _geo(String id, {required bool synced}) => GeoData(
      id: id,
      projectId: 'p',
      formData: const {},
      points: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isSynced: synced,
    );

final _records = [
  _geo('s1', synced: true),
  _geo('u1', synced: false),
  _geo('s2', synced: true),
];

void main() {
  test('hitung record yang sudah di server vs belum di-upload', () {
    final c = countLocalDelete(_records);
    expect((c.onServer, c.notUploaded, c.total), (2, 1, 3));
  });

  test('clear local data: bawaan hanya record yang sudah di server', () {
    expect(clearLocalIds(_records, includeNotUploaded: false), ['s1', 's2']);
  });

  test('clear local data + centang: record belum di-upload ikut', () {
    expect(clearLocalIds(_records, includeNotUploaded: true), ['s1', 'u1', 's2']);
  });
}
