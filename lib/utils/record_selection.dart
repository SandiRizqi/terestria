/// Pilihan record di daftar data project (mode pilih). Tak bisa diubah:
/// setiap aksi mengembalikan pilihan baru.
class RecordSelection {
  final Set<String> ids;

  const RecordSelection([this.ids = const {}]);

  bool get isEmpty => ids.isEmpty;
  int get count => ids.length;
  bool contains(String id) => ids.contains(id);

  RecordSelection toggle(String id) => RecordSelection(
      ids.contains(id) ? ids.difference({id}) : {...ids, id});

  /// Semua record yang [visible] terpilih (daftar kosong → false).
  bool allSelected(Iterable<String> visible) =>
      visible.isNotEmpty && visible.every(ids.contains);

  /// "Pilih semua" hanya untuk record yang terlihat (setelah filter/cari);
  /// bila semuanya sudah terpilih, semuanya dilepas.
  RecordSelection toggleAll(Iterable<String> visible) => allSelected(visible)
      ? RecordSelection(ids.difference(visible.toSet()))
      : RecordSelection({...ids, ...visible});

  /// Lepas record yang tidak terlihat lagi (filter berubah, record dihapus),
  /// supaya aksi tidak mengenai record tersembunyi.
  RecordSelection retain(Iterable<String> visible) =>
      RecordSelection(ids.intersection(visible.toSet()));
}
