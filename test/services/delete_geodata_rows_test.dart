import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Hapus banyak record lokal sekaligus (dijalankan di dalam satu transaksi
/// oleh `DatabaseService.deleteGeoDataBatch`): baris record dan konfliknya,
/// dipecah per potongan agar tidak melebihi batas parameter SQLite.

class _Delete {
  final String table;
  final String? where;
  final List<Object?>? args;
  _Delete(this.table, this.where, this.args);
}

class _FakeExecutor implements DatabaseExecutor {
  final deletes = <_Delete>[];

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    deletes.add(_Delete(table, where, whereArgs));
    // Anggap setiap id ada di tabel record.
    return table == 'geo_data' ? whereArgs!.length : 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('menghapus record dan konfliknya; mengembalikan jumlah record', () async {
    final db = _FakeExecutor();
    final count = await deleteGeoDataRows(db, ['a', 'b']);

    expect(count, 2);
    expect(db.deletes.map((d) => d.table), ['geo_data', 'sync_conflicts']);
    expect(db.deletes[0].where, 'id IN (?, ?)');
    expect(db.deletes[0].args, ['a', 'b']);
    expect(db.deletes[1].where, 'geoDataId IN (?, ?)');
    expect(db.deletes[1].args, ['a', 'b']);
  });

  test('banyak id dipecah per 500 (batas parameter SQLite)', () async {
    final db = _FakeExecutor();
    final ids = [for (var i = 0; i < 1204; i++) 'g$i'];
    final count = await deleteGeoDataRows(db, ids);

    expect(count, 1204);
    final recordDeletes = db.deletes.where((d) => d.table == 'geo_data').toList();
    expect(recordDeletes.map((d) => d.args!.length), [500, 500, 204]);
    expect(recordDeletes.expand((d) => d.args!), ids);
  });

  test('tanpa id → tidak menyentuh DB', () async {
    final db = _FakeExecutor();
    expect(await deleteGeoDataRows(db, const []), 0);
    expect(db.deletes, isEmpty);
  });
}
