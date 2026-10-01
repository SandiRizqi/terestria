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

  testWidgets('teks panjang bisa dipilih', (tester) async {
    final result = await _openDialog(tester);
    await _pickType(tester, 'Long text');
    await tester.enterText(find.widgetWithText(TextFormField, 'Field Label'), 'Catatan');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result()?.type, FieldType.textarea);
  });
}
