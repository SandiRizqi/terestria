import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/field_type_info.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/widgets/project/project_rules_section.dart';

/// Bagian "Project rules" di pembuat project HP (SPEC §3.5): akurasi
/// minimum (0,01–500 m, opsional) dan kombinasi unik (≤ 5 field yang
/// memenuhi syarat, disimpan sebagai label, dilacak lewat id field).

final _fields = [
  FormFieldModel(id: 'f1', label: 'WERKS', type: FieldType.text),
  FormFieldModel(id: 'f2', label: 'Foto', type: FieldType.photo),
  FormFieldModel(id: 'f3', label: 'NO_TPH', type: FieldType.number),
  FormFieldModel(id: 'f4', label: 'Catatan', type: FieldType.textarea),
  FormFieldModel.fromJson({'id': 'f5', 'label': 'TTD', 'type': 'signature'}),
];

void main() {
  group('aturan murni', () {
    test('akurasi minimum: kosong = tanpa aturan; 0,01–500; koma diterima', () {
      expect(minAccuracyInputIssue(''), isNull);
      expect(minAccuracyInputIssue(' 5 '), isNull);
      expect(minAccuracyInputIssue('2,5'), isNull);
      expect(minAccuracyFromInput('2,5'), 2.5);
      expect(minAccuracyFromInput(''), isNull);
      for (final bad in ['0', '0.009', '500.1', '-1', 'lima']) {
        expect(minAccuracyInputIssue(bad), 'Must be between 0.01 and 500 m', reason: bad);
        expect(minAccuracyFromInput(bad), isNull, reason: bad);
      }
    });

    test('field kunci: bukan foto dan bukan teks panjang', () {
      expect(canBeUniqueKey(_fields[0]), isTrue);
      expect(canBeUniqueKey(_fields[1]), isFalse);
      expect(canBeUniqueKey(_fields[2]), isTrue);
      expect(canBeUniqueKey(_fields[3]), isFalse);
      expect(canBeUniqueKey(_fields[4]), isTrue); // tipe tak dikenal = teks
    });

    test('label tersimpan → id: urutan tetap; tak ada / tak memenuhi syarat dibuang', () {
      expect(uniqueFieldIdsFromLabels(_fields, ['NO_TPH', 'WERKS', 'Foto', 'Hilang']),
          ['f3', 'f1']);
    });

    test('id → label: ikut ganti nama, field terhapus / berubah tipe keluar', () {
      final renamed = [
        FormFieldModel(id: 'f1', label: 'KEBUN', type: FieldType.text),
        FormFieldModel(id: 'f3', label: 'NO_TPH', type: FieldType.textarea),
      ];
      expect(uniqueFieldLabels(_fields, ['f3', 'f1']), ['NO_TPH', 'WERKS']);
      expect(uniqueFieldLabels(renamed, ['f3', 'f1', 'f2']), ['KEBUN']);
    });

    test('field kunci otomatis wajib, field lain tidak berubah', () {
      final result = withRequiredKeyFields(_fields, ['f3']);
      expect(result[2].required, isTrue);
      expect(result[0].required, isFalse);
      expect(result[2].label, 'NO_TPH');
      expect(result[2].type, FieldType.number);
    });
  });

  group('widget', () {
    Future<List<String> Function()> pump(WidgetTester tester,
        {List<String> ids = const [], List<FormFieldModel>? fields}) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var current = ids;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => Form(
                child: ProjectRulesSection(
                  minAccuracyController: controller,
                  fields: fields ?? _fields,
                  uniqueFieldIds: current,
                  onUniqueFieldIdsChanged: (v) => setState(() => current = v),
                ),
              ),
            ),
          ),
        ),
      ));
      return () => current;
    }

    testWidgets('pilih field kunci dari daftar yang memenuhi syarat', (tester) async {
      final ids = await pump(tester);
      await tester.tap(find.text('Add field'));
      await tester.pumpAndSettle();
      expect(find.text('Foto'), findsNothing);
      expect(find.text('Catatan'), findsNothing);
      await tester.tap(find.text('NO_TPH').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add field'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WERKS').last);
      await tester.pumpAndSettle();
      expect(ids(), ['f3', 'f1']);
      expect(find.textContaining('NO_TPH + WERKS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hapus field dari kombinasi', (tester) async {
      final ids = await pump(tester, ids: ['f1', 'f3']);
      await tester.tap(find.byTooltip('Remove WERKS from the combination'));
      await tester.pumpAndSettle();
      expect(ids(), ['f3']);
    });

    testWidgets('maksimal 5 field', (tester) async {
      final many = [
        for (var i = 1; i <= 6; i++)
          FormFieldModel(id: 'k$i', label: 'K$i', type: FieldType.text),
      ];
      await pump(tester, fields: many, ids: ['k1', 'k2', 'k3', 'k4', 'k5']);
      final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Add field'));
      expect(button.onPressed, isNull);
      expect(find.textContaining('at most 5'), findsOneWidget);
    });

    testWidgets('akurasi minimum divalidasi', (tester) async {
      await pump(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Minimum accuracy (m)'), '0');
      final form = tester.state<FormState>(find.byType(Form));
      expect(form.validate(), isFalse);
      await tester.pump();
      expect(find.text('Must be between 0.01 and 500 m'), findsOneWidget);
    });
  });
}
