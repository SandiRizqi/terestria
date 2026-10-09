import '../models/geo_data_model.dart';

/// Hapus data project dari HP saja (tidak ada penghapusan di server).
/// Record yang sudah di server bisa diambil lagi lewat Pull; record yang
/// belum di-upload hilang permanen.

class LocalDeleteCounts {
  final int onServer;
  final int notUploaded;

  const LocalDeleteCounts({required this.onServer, required this.notUploaded});

  int get total => onServer + notUploaded;
}

LocalDeleteCounts countLocalDelete(Iterable<GeoData> records) {
  var onServer = 0, notUploaded = 0;
  for (final r in records) {
    r.isSynced ? onServer++ : notUploaded++;
  }
  return LocalDeleteCounts(onServer: onServer, notUploaded: notUploaded);
}

/// Record yang dihapus "Clear local data": yang sudah di server, ditambah
/// yang belum di-upload hanya bila user mencentangnya. Urutan dipertahankan.
List<String> clearLocalIds(Iterable<GeoData> records,
        {required bool includeNotUploaded}) =>
    [
      for (final r in records)
        if (r.isSynced || includeNotUploaded) r.id,
    ];
