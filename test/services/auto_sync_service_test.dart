// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/auto_sync_service.dart';
import 'package:geoform_app/services/sync_service.dart';

FullSyncResult _result({int ok = 1, int fail = 0, bool offline = false}) =>
    FullSyncResult(
      projectsTotal: 0,
      projectsSuccess: 0,
      projectsFail: 0,
      geoDataTotal: ok + fail,
      geoDataSuccess: ok,
      geoDataFail: fail,
      errors: fail > 0 ? ['x'] : const [],
      abortedDueToConnection: offline,
    );

void main() {
  test('reset() (logout) menghapus backoff & status run terakhir user lama',
      () async {
    var runs = 0;
    final svc = AutoSyncService(
      isOnline: () => true,
      onlineChanges: const Stream<bool>.empty(),
      syncAll: () async {
        runs++;
        return _result(ok: 0, fail: 1);
      },
      isSyncing: ValueNotifier(false),
      enabled: () => true,
      pendingCount: () async => 1,
      authBlocked: () => false,
      loggedIn: () async => true,
      now: () => DateTime(2026, 9, 30, 8),
    );

    expect(await svc.runNow('test'), isTrue); // gagal → backoff 1 menit
    expect(svc.lastRun.value?.ok, isFalse);
    expect(await svc.runNow('test'), isFalse, reason: 'backing off');

    svc.reset();

    expect(svc.lastRun.value, isNull);
    expect(await svc.runNow('test'), isTrue,
        reason: 'the next user must not inherit the backoff');
    expect(runs, 2);
  });

  test('backoffFor: 0, 1, 2, 4 … maks 30 menit', () {
    expect(AutoSyncService.backoffFor(0), Duration.zero);
    expect(AutoSyncService.backoffFor(1), const Duration(minutes: 1));
    expect(AutoSyncService.backoffFor(3), const Duration(minutes: 4));
    expect(AutoSyncService.backoffFor(10), const Duration(minutes: 30));
  });

  test('online kembali → sync setelah debounce; tak jalan bila mati/offline/'
      'sesi kedaluwarsa/tak ada data', () {
    fakeAsync((async) {
      var enabled = true, online = false, expired = false, pending = 3;
      var runs = 0;
      final changes = StreamController<bool>.broadcast();
      var now = DateTime(2026, 9, 29, 8);
      final svc = AutoSyncService(
        isOnline: () => online,
        onlineChanges: changes.stream,
        syncAll: () async {
          runs++;
          return _result();
        },
        isSyncing: ValueNotifier(false),
        enabled: () => enabled,
        pendingCount: () async => pending,
        authBlocked: () => expired,
        loggedIn: () async => true,
        now: () => now,
        debounce: const Duration(seconds: 15),
      );
      svc.start();
      async.elapse(const Duration(minutes: 1));
      expect(runs, 0, reason: 'offline');

      online = true;
      changes.add(true);
      async.elapse(const Duration(seconds: 10));
      expect(runs, 0, reason: 'masih dalam debounce');
      async.elapse(const Duration(seconds: 6));
      expect(runs, 1);
      expect(svc.lastRun.value?.ok, isTrue);

      // Sesi kedaluwarsa → dilewati.
      expired = true;
      changes.add(true);
      async.elapse(const Duration(seconds: 20));
      expect(runs, 1);
      expired = false;

      // Tak ada data tertunda → tak memanggil sync.
      pending = 0;
      changes.add(true);
      async.elapse(const Duration(seconds: 20));
      expect(runs, 1);
      pending = 2;

      // Dimatikan di Settings.
      enabled = false;
      changes.add(true);
      async.elapse(const Duration(seconds: 20));
      expect(runs, 1);

      svc.stop();
      changes.close();
    });
  });

  test('gagal → jeda sebelum mencoba lagi', () {
    fakeAsync((async) {
      var runs = 0;
      var now = DateTime(2026, 9, 29, 8);
      final svc = AutoSyncService(
        isOnline: () => true,
        onlineChanges: const Stream<bool>.empty(),
        syncAll: () async {
          runs++;
          return _result(ok: 0, fail: 2);
        },
        isSyncing: ValueNotifier(false),
        enabled: () => true,
        pendingCount: () async => 2,
        authBlocked: () => false,
        loggedIn: () async => true,
        now: () => now,
      );
      Future<bool> run() {
        late bool r;
        svc.runNow('test').then((v) => r = v);
        async.flushMicrotasks();
        return Future.value(r);
      }

      run();
      expect(runs, 1);
      expect(svc.lastRun.value?.ok, isFalse);
      // 30 dtk kemudian: masih dalam jeda 1 menit.
      now = now.add(const Duration(seconds: 30));
      run();
      expect(runs, 1);
      now = now.add(const Duration(minutes: 1));
      run();
      expect(runs, 2);
    });
  });
}
