import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/widgets/dynamic_form.dart';

/// Nilai default di form HP (SPEC §3.4): hanya record baru
/// (`applyDefaults`), hanya field yang belum punya isian; prioritas
/// draft → pin → default.

final _fields = [
  FormFieldModel(id: 'b', label: 'Blok', type: FieldType.text, defaultValue: 'A1'),
  FormFieldModel(
      id: 'j', label: 'Jumlah', type: FieldType.number, defaultValue: '3'),
  FormFieldModel(
      id: 'p', label: 'Panen', type: FieldType.checkbox, defaultValue: 'true'),
  FormFieldModel(id: 't', label: 'Jam', type: FieldType.time, defaultValue: 'now'),
];

Future<Map<String, dynamic> Function()> _pump(
  WidgetTester tester, {
  required bool applyDefaults,
  Map<String, dynamic>? initial,
  String? projectId,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var saved = <String, dynamic>{};
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Form(
          child: DynamicForm(
            formFields: _fields,
            initialData: initial,
            projectId: projectId,
            applyDefaults: applyDefaults,
            onSaved: (data) => saved = Map.of(data),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return () => saved;
}

String _text(WidgetTester tester, String label) => tester
    .widget<TextField>(find.descendant(
        of: find.widgetWithText(TextFormField, label),
        matching: find.byType(TextField)))
    .controller!
    .text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('record baru: default terisi, tampil, dan dilaporkan ke induk',
      (tester) async {
    final saved = await _pump(tester, applyDefaults: true);
    expect(_text(tester, 'Blok'), 'A1');
    expect(_text(tester, 'Jumlah'), '3');
    expect(saved()['Blok'], 'A1');
    expect(saved()['Jumlah'], 3);
    expect(saved()['Panen'], true);
    expect(saved()['Jam'], matches(RegExp(r'^\d{2}:\d{2}$')));
  });

  testWidgets('tanpa applyDefaults (layar edit): default tidak dipakai',
      (tester) async {
    final saved = await _pump(tester, applyDefaults: false);
    expect(_text(tester, 'Blok'), '');
    expect(saved().containsKey('Blok'), isFalse);
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('draft menang: nilai draft & isian yang dikosongkan tetap',
      (tester) async {
    final saved = await _pump(tester,
        applyDefaults: true, initial: {'Blok': 'B7', 'Jumlah': ''});
    expect(_text(tester, 'Blok'), 'B7');
    expect(_text(tester, 'Jumlah'), '');
    expect(saved()['Panen'], true);
  });

  testWidgets('nilai pin menang atas default', (tester) async {
    SharedPreferences.setMockInitialValues({'pinned_p1_Blok': '"PIN"'});
    final saved = await _pump(tester, applyDefaults: true, projectId: 'p1');
    expect(_text(tester, 'Blok'), 'PIN');
    expect(saved()['Blok'], 'PIN');
    expect(saved()['Jumlah'], 3);
  });
}
