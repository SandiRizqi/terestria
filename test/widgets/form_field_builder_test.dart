import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/widgets/form_field_builder.dart';

/// Pembuat field di HP: tipe yang ditawarkan mengikuti daftar tipe
/// (`field_type_info.dart`).

Future<FormFieldModel? Function()> _openDialog(WidgetTester tester,
    {FormFieldModel? field}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FormFieldModel? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => result = await showDialog<FormFieldModel>(
              context: context,
              builder: (_) => FormFieldBuilderDialog(field: field),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

Future<void> _pickType(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<FieldType>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menawarkan teks panjang & skala; membuat field bertipe itu',
      (tester) async {
    final result = await _openDialog(tester);
    await tester.tap(find.byType(DropdownButtonFormField<FieldType>));
    await tester.pumpAndSettle();
    expect(find.text('Long text'), findsWidgets);
    expect(find.text('Rating (1–5)'), findsWidgets);
    await tester.tap(find.text('Rating (1–5)').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Field Label'), 'Kondisi');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result()?.type, FieldType.rating);
    expect(result()?.label, 'Kondisi');
  });

  testWidgets('pilihan ganda: opsi wajib, tanpa ";" dan tanpa duplikat',
      (tester) async {
    final result = await _openDialog(tester);
    await _pickType(tester, 'Multiple choice');
    await tester.enterText(find.widgetWithText(TextFormField, 'Field Label'), 'Hama');
    final options = find.widgetWithText(TextFormField, 'Options (one per line)');

    await tester.enterText(options, 'Ulat api\nTikus; Babi');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
    expect(find.textContaining('";"'), findsOneWidget);

    await tester.enterText(options, 'Ulat api\nTikus\nulat api ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
    expect(find.textContaining('twice'), findsOneWidget);

    await tester.enterText(options, 'Ulat api\nTikus');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result()?.type, FieldType.multiselect);
    expect(result()?.options, ['Ulat api', 'Tikus']);
  });

  testWidgets('waktu & tanggal-waktu bisa dipilih', (tester) async {
    final result = await _openDialog(tester);
    await _pickType(tester, 'Time');
    await tester.enterText(find.widgetWithText(TextFormField, 'Field Label'), 'Jam');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result()?.type, FieldType.time);

    final result2 = await _openDialog(tester);
    await _pickType(tester, 'Date & time');
    await tester.enterText(find.widgetWithText(TextFormField, 'Field Label'), 'Mulai');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result2()?.type, FieldType.datetime);
    expect(tester.takeException(), isNull);
  });

  testWidgets('angka: min/maks/satuan tersimpan; min > maks ditolak',
      (tester) async {
    final result = await _openDialog(tester);
    await _pickType(tester, 'Decimal');
    await tester.enterText(find.widgetWithText(TextFormField, 'Field Label'), 'Tinggi');
    await tester.enterText(find.widgetWithText(TextFormField, 'Min'), '200');
    await tester.enterText(find.widgetWithText(TextFormField, 'Max'), '0');
    await tester.enterText(find.widgetWithText(TextFormField, 'Unit'), ' cm ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
    expect(find.text('Must not be less than Min'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Min'), '0');
    await tester.enterText(find.widgetWithText(TextFormField, 'Max'), '200,5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result()?.min, 0);
    expect(result()?.max, 200.5);
    expect(result()?.unit, 'cm');
    expect(tester.takeException(), isNull);
  });

  testWidgets('angka: batas boleh salah satu; isian kosong = tanpa batas',
      (tester) async {
    final result = await _openDialog(tester);
    await _pickType(tester, 'Number');
    await tester.enterText(find.widgetWithText(TextFormField, 'Field Label'), 'Jumlah');
    await tester.enterText(find.widgetWithText(TextFormField, 'Min'), '1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result()?.min, 1);
    expect(result()?.max, isNull);
    expect(result()?.unit, isNull);
  });

  testWidgets('batas lama tampil saat edit; pindah ke teks → batas dibuang',
      (tester) async {
    final result = await _openDialog(tester,
        field: FormFieldModel(
            id: 'x',
            label: 'Tinggi',
            type: FieldType.number,
            min: 0,
            max: 10.5,
            unit: 'm'));
    expect(find.widgetWithText(TextFormField, '10.5'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '0'), findsOneWidget);
    await _pickType(tester, 'Text');
    expect(find.widgetWithText(TextFormField, 'Min'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result()?.type, FieldType.text);
    expect(result()?.min, isNull);
    expect(result()?.max, isNull);
    expect(result()?.unit, isNull);
  });

  testWidgets('teks panjang bisa dipilih', (tester) async {
    final result = await _openDialog(tester);
    await _pickType(tester, 'Long text');
    await tester.enterText(find.widgetWithText(TextFormField, 'Field Label'), 'Catatan');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result()?.type, FieldType.textarea);
  });
}
