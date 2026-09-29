import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/logging/app_log.dart';
import 'package:geoform_app/services/logging/crashlytics_forwarder.dart';
import 'package:geoform_app/utils/app_logger.dart';

void main() {
  late List<String> crumbs;
  late List<(Object, String?)> records;
  late DateTime clock;
  late CrashlyticsLogForwarder fwd;

  setUp(() {
    crumbs = [];
    records = [];
    clock = DateTime(2026, 9, 29, 8);
    fwd = CrashlyticsLogForwarder(
      breadcrumb: crumbs.add,
      recordError: (e, s, reason) => records.add((e, reason)),
      now: () => clock,
    );
  });

  test('warn & error jadi breadcrumb; debug/info tidak', () {
    fwd(LogLevel.debug, 'GPS', 'fix');
    fwd(LogLevel.info, 'SESSION', 'start');
    fwd(LogLevel.warn, 'ENGINE', 'restart');
    fwd(LogLevel.error, 'SERVICE', 'mati');
    expect(crumbs, ['W ENGINE restart', 'E SERVICE mati']);
    expect(records, isEmpty); // error tanpa objek error → breadcrumb saja
  });

  test('error dengan objek error → non-fatal, dibatasi 1× per 5 menit', () {
    final e = StateError('x');
    fwd(LogLevel.error, 'SYNC', 'upload gagal', e, StackTrace.empty);
    fwd(LogLevel.error, 'SYNC', 'upload gagal', e, StackTrace.empty);
    expect(records.length, 1);
    expect(records.single.$2, 'SYNC: upload gagal');

    clock = clock.add(const Duration(minutes: 4));
    fwd(LogLevel.error, 'SYNC', 'upload gagal', e, StackTrace.empty);
    expect(records.length, 1);

    clock = clock.add(const Duration(minutes: 2));
    fwd(LogLevel.error, 'SYNC', 'upload gagal', e, StackTrace.empty);
    expect(records.length, 2);

    fwd(LogLevel.error, 'SYNC', 'pesan lain', e, StackTrace.empty);
    expect(records.length, 3);
  });

  test('breadcrumb panjang dipotong', () {
    fwd(LogLevel.warn, 'X', 'a' * 5000);
    expect(crumbs.single.length, lessThanOrEqualTo(1024));
  });

  group('AppLogger → hook', () {
    tearDown(() => AppLogger.onWarnOrError = null);

    test('logError meneruskan error & stack ke hook', () {
      Object? got;
      AppLogger.consoleEnabled = false;
      AppLogger.onWarnOrError = (level, tag, msg, [error, stack]) => got = error;
      final err = ArgumentError('y');
      logError('gagal', tag: 'APP', error: err);
      expect(got, same(err));
    });

    test('forward:false tak memanggil hook (cegah putaran Crashlytics)', () {
      var calls = 0;
      AppLogger.consoleEnabled = false;
      AppLogger.onWarnOrError = (level, tag, msg, [error, stack]) => calls++;
      AppLogger.log(LogLevel.error, 'dari crashlytics', forward: false);
      expect(calls, 0);
    });
  });
}
