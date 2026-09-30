import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/database_service.dart';

/// Selama reset logout DB terkunci: penulis yang terlambat (pull/sync yang
/// melewati batas tunggu) GAGAL alih-alih membuka ulang `geoform.db` baru dan
/// menulis data user lama ke dalamnya.
void main() {
  tearDown(() => DatabaseService().unlockAfterReset());

  test('terkunci → akses DB melempar DatabaseResetInProgress tanpa membuka '
      'berkas', () async {
    await DatabaseService().lockForReset();
    expect(DatabaseService.isLockedForReset, isTrue);
    await expectLater(
        DatabaseService().database, throwsA(isA<DatabaseResetInProgress>()));
  });

  test('dibuka lagi → akses DB tak lagi ditolak oleh kunci reset', () async {
    await DatabaseService().lockForReset();
    DatabaseService().unlockAfterReset();
    expect(DatabaseService.isLockedForReset, isFalse);
    // Di VM test tak ada factory sqflite: yang penting BUKAN error kunci.
    await expectLater(DatabaseService().database,
        throwsA(isNot(isA<DatabaseResetInProgress>())));
  });
}
