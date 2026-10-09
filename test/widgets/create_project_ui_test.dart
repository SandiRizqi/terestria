import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/screens/project/create_project_screen.dart';
import 'package:geoform_app/services/connectivity_service.dart';
import 'package:geoform_app/widgets/project/create_project_parts.dart';
import 'package:geoform_app/widgets/project/create_project_source_sheet.dart';

/// Buat project seperti template: sheet pilih sumber dan layar "New project"
/// (pilihan geometri, kartu field berlencana tipe, tombol Add Field).

Future<CreateProjectSource?> _openSheet(
    WidgetTester tester, Future<void> Function() act) async {
  CreateProjectSource? result;
  var closed = false;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await showCreateProjectSourceSheet(context);
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
  expect(closed, isTrue);
  return result;
}

void main() {
  group('sheet pilih sumber', () {
    for (final (label, source) in [
      ('Start from scratch', CreateProjectSource.scratch),
      ('Import template', CreateProjectSource.template),
      ('From server', CreateProjectSource.server),
    ]) {
      testWidgets('"$label" → $source', (tester) async {
        final r = await _openSheet(tester, () async {
          expect(find.text('Create Project'), findsOneWidget);
          expect(find.text('How would you like to create your project?'),
              findsOneWidget);
          await tester.tap(find.text(label));
        });
        expect(r, source);
      });
    }

    testWidgets('Cancel → null', (tester) async {
      final r = await _openSheet(tester, () => tester.tap(find.text('Cancel')));
      expect(r, isNull);
    });
  });

  group('fieldCardSubtitle', () {
    FormFieldModel f(FieldType type,
            {bool required = false,
            List<String>? options,
            double? min,
            double? max,
            String? unit,
            int? minPhotos,
            int? maxPhotos}) =>
        FormFieldModel(
          id: 'x',
          label: 'X',
          type: type,
          required: required,
          options: options,
          min: min,
          max: max,
          unit: unit,
          minPhotos: minPhotos,
          maxPhotos: maxPhotos,
        );

    test('opsi dropdown / pilihan ganda', () {
      expect(
          fieldCardSubtitle(
              f(FieldType.dropdown, options: ['Mature', 'Young', 'Replant']),
              isUniqueKey: false),
          'Mature, Young, Replant');
    });
    test('batas angka + satuan', () {
      expect(fieldCardSubtitle(f(FieldType.decimal, min: 0, max: 200, unit: 'cm'),
          isUniqueKey: false), '0–200 cm');
      expect(fieldCardSubtitle(f(FieldType.number, min: 1), isUniqueKey: false),
          '≥ 1');
      expect(fieldCardSubtitle(f(FieldType.number, max: 50), isUniqueKey: false),
          '≤ 50');
    });
    test('jumlah foto', () {
      expect(fieldCardSubtitle(f(FieldType.photo, minPhotos: 1, maxPhotos: 4),
          isUniqueKey: false), 'Min 1 · max 4');
    });
    test('selain itu: Required, atau keterangan tipe; + Unique key', () {
      expect(fieldCardSubtitle(f(FieldType.text, required: true),
          isUniqueKey: false), 'Required');
      expect(fieldCardSubtitle(f(FieldType.number), isUniqueKey: false),
          'Whole number');
      expect(fieldCardSubtitle(f(FieldType.text, required: true),
          isUniqueKey: true), 'Required · Unique key');
    });
  });

  group('kartu field', () {
    final field = FormFieldModel(
      id: 'c',
      label: 'Condition',
      type: FieldType.dropdown,
      required: true,
      options: const ['Mature', 'Young'],
    );

    testWidgets('label + tanda wajib, ringkasan, lencana tipe; ketuk & hapus',
        (tester) async {
      var taps = 0, deletes = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FormFieldCard(
            field: field,
            isUniqueKey: false,
            onTap: () => taps++,
            onDelete: () => deletes++,
          ),
        ),
      ));
      expect(find.text('Condition'), findsOneWidget);
      expect(find.text('*'), findsOneWidget);
      expect(find.text('Mature, Young'), findsOneWidget);
      expect(find.text('dropdown'), findsOneWidget);
      await tester.tap(find.text('Condition'));
      await tester.tap(find.byTooltip('Delete field'));
      expect((taps, deletes), (1, 1));
    });

    testWidgets('tanpa onDelete/onTap (edit project) → tanpa tombol hapus',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FormFieldCard(field: field, isUniqueKey: false),
        ),
      ));
      expect(find.byTooltip('Delete field'), findsNothing);
    });
  });

  group('pilihan geometri', () {
    testWidgets('ketuk segmen → onChanged; nonaktif → tidak berubah',
        (tester) async {
      GeometryType? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GeometrySegmentedControl(
            value: GeometryType.point,
            onChanged: (g) => picked = g,
          ),
        ),
      ));
      await tester.tap(find.text('Polygon'));
      expect(picked, GeometryType.polygon);

      picked = null;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GeometrySegmentedControl(
            value: GeometryType.point,
            onChanged: null,
          ),
        ),
      ));
      await tester.tap(find.text('Line'));
      expect(picked, isNull);
    });
  });

  testWidgets('tombol Add Field bergaris putus', (tester) async {
    var adds = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashedAddButton(label: 'Add Field', onPressed: () => adds++),
      ),
    ));
    await tester.tap(find.text('Add Field'));
    expect(adds, 1);
  });

  testWidgets('layar New project: judul, Save, field bawaan, Add Field',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CreateProjectScreen()));
    await tester.pump();

    expect(find.text('New project'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.text('FORM FIELDS · 1'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Add Field'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Add Field'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    ConnectivityService().stopMonitoring();
    await tester.pump(const Duration(seconds: 6));
  });
}
