import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/sync_service.dart';
import 'package:geoform_app/widgets/sync/sync_result_dialog.dart';

/// Hasil sync di Beranda / sebelum logout / Readiness: bila ada yang gagal,
/// user melihat ALASANNYA (mis. project nonaktif), bukan sekadar "3/5 synced".

const _inactive =
    'Blok A: Project "Blok A" is not accepting data right now (inactive).';

FullSyncResult _result({
  int ok = 0,
  int fail = 0,
  List<String> errors = const [],
  bool offline = false,
  bool auth = false,
}) =>
    FullSyncResult(
      projectsTotal: 0,
      projectsSuccess: 0,
      projectsFail: 0,
      geoDataTotal: ok + fail,
      geoDataSuccess: ok,
      geoDataFail: fail,
      errors: errors,
      abortedDueToConnection: offline,
      abortedDueToAuth: auth,
    );

Future<void> _show(WidgetTester tester, FullSyncResult result,
    {VoidCallback? onRetry}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showFullSyncResult(context, result, onRetry: onRetry),
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sebagian gagal → dialog dengan alasan yang dikelompokkan',
      (tester) async {
    var retries = 0;
    await _show(
        tester,
        _result(ok: 1, fail: 2, errors: [_inactive, _inactive]),
        onRetry: () => retries++);

    expect(find.text('Some records were not uploaded'), findsOneWidget);
    expect(find.textContaining('1 of 3 records uploaded'), findsOneWidget);
    expect(find.textContaining('not accepting data right now (inactive). (2×)'),
        findsOneWidget);
    expect(tester.takeException(), isNull); // muat di 360 dp

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(find.text('Some records were not uploaded'), findsNothing);
  });

  testWidgets('semua gagal → judul "Nothing was uploaded"', (tester) async {
    await _show(tester, _result(fail: 1, errors: [_inactive]));
    expect(find.text('Nothing was uploaded'), findsOneWidget);
    expect(find.text('Retry'), findsNothing, reason: 'no retry callback');
  });

  testWidgets('berhasil semua → snackbar, tanpa dialog', (tester) async {
    await _show(tester, _result(ok: 3));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('server tak terjangkau / sesi habis → snackbar penjelasan',
      (tester) async {
    await _show(tester, _result(fail: 3, offline: true, errors: ['x']));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('could not be reached'), findsOneWidget);
  });
}
