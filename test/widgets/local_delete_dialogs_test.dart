import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/widgets/project/local_delete_dialogs.dart';

/// Dialog peringatan sebelum menghapus data project dari HP.

GeoData _geo(String id, {required bool synced}) => GeoData(
      id: id,
      projectId: 'p',
      formData: const {},
      points: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isSynced: synced,
    );

/// Buka dialog lewat tombol, lalu kembalikan hasilnya setelah ditutup.
Future<T?> _open<T>(WidgetTester tester,
    Future<T?> Function(BuildContext) show, Future<void> Function() act) async {
  T? result;
  var closed = false;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await show(context);
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await act();
  await tester.pumpAndSettle();
  expect(closed, isTrue, reason: 'dialog harus tertutup');
  return result;
}

void main() {
  group('hapus terpilih', () {
    final records = [
      _geo('s1', synced: true),
      _geo('s2', synced: true),
      _geo('u1', synced: false),
    ];

    testWidgets('menyebut jumlah di server & yang hilang permanen; Delete → true',
        (tester) async {
      final ok = await _open<bool>(
        tester,
        (c) => confirmDeleteSelected(c, records),
        () async {
          expect(find.text('Delete 3 records from this phone?'), findsOneWidget);
          expect(find.textContaining('2 already on the server'), findsOneWidget);
          expect(find.textContaining('1 not uploaded yet'), findsOneWidget);
          expect(find.textContaining('lost permanently'), findsOneWidget);
          expect(find.textContaining('Nothing is deleted on the server'),
              findsOneWidget);
          await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        },
      );
      expect(ok, isTrue);
    });

    testWidgets('Cancel → false; semua sudah di server → tanpa peringatan permanen',
        (tester) async {
      final ok = await _open<bool>(
        tester,
        (c) => confirmDeleteSelected(c, records.take(1).toList()),
        () async {
          expect(find.text('Delete 1 record from this phone?'), findsOneWidget);
          expect(find.textContaining('lost permanently'), findsNothing);
          await tester.tap(find.text('Cancel'));
        },
      );
      expect(ok, isFalse);
    });
  });

  group('kosongkan data lokal', () {
    final records = [
      _geo('s1', synced: true),
      _geo('u1', synced: false),
      _geo('s2', synced: true),
    ];

    testWidgets('bawaan: hanya record yang sudah di server', (tester) async {
      final ids = await _open<List<String>>(
        tester,
        (c) => confirmClearLocalData(c, records),
        () async {
          expect(find.text('Clear local data?'), findsOneWidget);
          expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
          await tester.tap(find.widgetWithText(FilledButton, 'Delete 2'));
        },
      );
      expect(ids, ['s1', 's2']);
    });

    testWidgets('centang "not uploaded yet" → ikut dihapus', (tester) async {
      final ids = await _open<List<String>>(
        tester,
        (c) => confirmClearLocalData(c, records),
        () async {
          await tester.tap(find.byType(Checkbox));
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Delete 3'));
        },
      );
      expect(ids, ['s1', 'u1', 's2']);
    });

    testWidgets('hanya record belum di-upload & tak dicentang → Delete nonaktif',
        (tester) async {
      final ids = await _open<List<String>>(
        tester,
        (c) => confirmClearLocalData(c, [_geo('u1', synced: false)]),
        () async {
          final delete = tester.widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Delete 0'));
          expect(delete.onPressed, isNull);
          await tester.tap(find.text('Cancel'));
        },
      );
      expect(ids, isNull);
    });

    testWidgets('tanpa record belum di-upload → tanpa checkbox', (tester) async {
      await _open<List<String>>(
        tester,
        (c) => confirmClearLocalData(c, [_geo('s1', synced: true)]),
        () async {
          expect(find.byType(Checkbox), findsNothing);
          await tester.tap(find.text('Cancel'));
        },
      );
    });
  });
}
