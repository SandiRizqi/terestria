import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/widgets/dynamic_form.dart';

/// Input tipe field baru di form HP (SPEC §3.1), lebar 360 dp.

class _Harness {
  final GlobalKey<FormState> formKey;
  final Map<String, dynamic> Function() saved;
  _Harness(this.formKey, this.saved);
}

Future<_Harness> _pump(WidgetTester tester, List<FormFieldModel> fields,
    {Map<String, dynamic>? initial}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var saved = <String, dynamic>{};
  final key = GlobalKey<FormState>();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: key,
          child: DynamicForm(
            formFields: fields,
            initialData: initial,
            onSaved: (data) => saved = Map.of(data),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return _Harness(key, () => saved);
}

FormFieldModel _f(String label, FieldType type, {bool required = false}) =>
    FormFieldModel(id: label, label: label, type: type, required: required);

void main() {
  group('teks panjang', () {
    testWidgets('banyak baris, tanpa tombol QR, tersimpan apa adanya',
        (tester) async {
      final h = await _pump(tester, [_f('Catatan', FieldType.textarea)]);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, isNull);
      expect(field.minLines, 3);
      expect(find.byTooltip('Scan QR Code'), findsNothing);
      await tester.enterText(find.byType(TextField), 'baris 1\nbaris 2');
      expect(h.saved()['Catatan'], 'baris 1\nbaris 2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('wajib: kosong ditolak', (tester) async {
      final h = await _pump(
          tester, [_f('Catatan', FieldType.textarea, required: true)]);
      expect(h.formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('This field is required'), findsOneWidget);
    });
  });

  group('pilihan ganda', () {
    FormFieldModel hama({bool required = false}) => FormFieldModel(
        id: 'h',
        label: 'Hama',
        type: FieldType.multiselect,
        required: required,
        options: const ['Ulat api', 'Tikus', 'Kumbang']);

    testWidgets('centang beberapa → "A; B" sesuai urutan opsi; lepas semua → kosong',
        (tester) async {
      final h = await _pump(tester, [hama()]);
      await tester.tap(find.text('Tikus'));
      await tester.pump();
      await tester.tap(find.text('Ulat api'));
      await tester.pump();
      expect(h.saved()['Hama'], 'Ulat api; Tikus');
      await tester.tap(find.text('Tikus'));
      await tester.pump();
      await tester.tap(find.text('Ulat api'));
      await tester.pump();
      expect(h.saved()['Hama'], '');
      expect(tester.takeException(), isNull);
    });

    testWidgets('nilai lama di luar daftar tampil & ditolak; wajib kosong ditolak',
        (tester) async {
      final h = await _pump(tester, [
        hama(),
        FormFieldModel(
            id: 'w',
            label: 'Wajib',
            type: FieldType.multiselect,
            required: true,
            options: const ['A']),
      ], initial: {'Hama': 'Tikus; Babi'});
      expect(find.textContaining('Babi'), findsOneWidget);
      expect(h.formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Value has an option that is not in the list: Babi'),
          findsOneWidget);
      expect(find.text('This field is required'), findsOneWidget);
    });
  });

  group('waktu & tanggal-waktu', () {
    testWidgets('"Now" mengisi format tersimpan; hapus → kosong',
        (tester) async {
      final h = await _pump(tester, [
        _f('Jam', FieldType.time),
        _f('Mulai', FieldType.datetime),
      ]);
      expect(find.text('Not set'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(TextButton, 'Now').first);
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Now').last);
      await tester.pump();
      expect(h.saved()['Jam'], matches(RegExp(r'^\d{2}:\d{2}$')));
      expect(h.saved()['Mulai'],
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00\.000$')));

      await tester.tap(find.byTooltip('Clear').first);
      await tester.pump();
      expect(h.saved()['Jam'], '');
      expect(find.text('Not set'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pemilih jam 24 jam; OK menyimpan HH:mm', (tester) async {
      final h = await _pump(tester, [_f('Jam', FieldType.time)],
          initial: {'Jam': '19:05'});
      await tester.tap(find.text('19:05'));
      await tester.pumpAndSettle();
      expect(find.text('PM'), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(h.saved()['Jam'], '19:05');
    });

    testWidgets('tanggal-waktu tampil terformat; pilih tanggal lalu jam',
        (tester) async {
      final h = await _pump(tester, [_f('Mulai', FieldType.datetime)],
          initial: {'Mulai': '2026-10-01T07:15:00.000'});
      await tester.tap(find.text('2026-10-01 07:15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // tanggal
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // jam
      await tester.pumpAndSettle();
      expect(h.saved()['Mulai'], '2026-10-01T07:15:00.000');
      expect(tester.takeException(), isNull);
    });

    testWidgets('nilai tak valid dari app lama tampil & ditolak',
        (tester) async {
      final h = await _pump(tester, [
        _f('Jam', FieldType.time),
        _f('Mulai', FieldType.datetime),
      ], initial: {'Jam': '7.15', 'Mulai': '2026-10-01'});
      expect(find.text('7.15'), findsOneWidget);
      expect(find.text('2026-10-01'), findsOneWidget);
      expect(h.formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Value is not a valid time'), findsOneWidget);
      expect(find.text('Value is not a valid date and time'), findsOneWidget);
    });
  });

  group('angka: batas & satuan', () {
    FormFieldModel tinggi(FieldType type) => FormFieldModel(
        id: 't', label: 'Tinggi', type: type, min: 0, max: 200, unit: 'cm');

    testWidgets('satuan tampil sebagai akhiran, juga saat masih kosong',
        (tester) async {
      await _pump(tester, [tinggi(FieldType.decimal)]);
      expect(find.text('cm'), findsOneWidget);
      final fades = tester.widgetList<AnimatedOpacity>(find.ancestor(
          of: find.text('cm'), matching: find.byType(AnimatedOpacity)));
      expect(fades.every((w) => w.opacity == 1), isTrue);
    });

    for (final type in [FieldType.number, FieldType.decimal]) {
      testWidgets('${type.name}: di luar batas ditolak; di dalam batas lolos',
          (tester) async {
        final field = tinggi(type);
        final h = await _pump(tester, [field]);
        await tester.enterText(find.byType(TextField), '250');
        expect(h.formKey.currentState!.validate(), isFalse);
        await tester.pump();
        expect(find.text('Value must be between 0 and 200 cm'), findsOneWidget);
        expect(formFieldIssues([field], h.saved()), isNotEmpty);

        await tester.enterText(find.byType(TextField), '35,5');
        expect(h.formKey.currentState!.validate(), isTrue);
        expect(h.saved()['Tinggi'], 35.5);
        expect(formFieldIssues([field], h.saved()), isEmpty);
      });
    }
  });

  group('skala 1–5', () {
    testWidgets('ketuk bintang → tersimpan angka; ketuk lagi → kosong',
        (tester) async {
      final h = await _pump(tester, [_f('Kondisi', FieldType.rating)]);
      expect(find.text('Not rated'), findsOneWidget);
      await tester.tap(find.byTooltip('Rate 4 of 5'));
      await tester.pump();
      expect(h.saved()['Kondisi'], 4);
      expect(find.text('4 / 5'), findsOneWidget);
      await tester.tap(find.byTooltip('Rate 4 of 5'));
      await tester.pump();
      expect(h.saved()['Kondisi'], isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wajib belum diisi dan nilai lama tak valid ditolak',
        (tester) async {
      final h = await _pump(tester, [
        _f('Kondisi', FieldType.rating, required: true),
        _f('Mutu', FieldType.rating),
      ], initial: {'Mutu': 'bagus'});
      expect(h.formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('This field is required'), findsOneWidget);
      expect(find.text('Value must be 1–5'), findsOneWidget);
    });

    testWidgets('nilai awal dari data tersimpan (teks angka)', (tester) async {
      await _pump(tester, [_f('Kondisi', FieldType.rating)],
          initial: {'Kondisi': '3'});
      expect(find.text('3 / 5'), findsOneWidget);
    });
  });
}
