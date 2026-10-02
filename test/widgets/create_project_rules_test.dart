import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/screens/project/create_project_screen.dart';
import 'package:geoform_app/services/connectivity_service.dart';

/// Layar edit project memuat aturan project yang tersimpan (mis. dari web).

void main() {
  testWidgets('edit project: aturan tersimpan tampil di "Project rules"',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final project = Project(
      id: 'p1',
      name: 'Sensus TPH',
      description: 'Blok A',
      geometryType: GeometryType.point,
      formFields: [
        FormFieldModel(id: 'f1', label: 'WERKS', type: FieldType.text, required: true),
        FormFieldModel(id: 'f2', label: 'NO_TPH', type: FieldType.number, required: true),
      ],
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      minAccuracy: 2.5,
      uniqueFields: const ['NO_TPH', 'WERKS'],
    );
    await tester.pumpWidget(MaterialApp(home: CreateProjectScreen(project: project)));
    await tester.pump();

    await tester.scrollUntilVisible(find.text('Project rules'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.widgetWithText(TextFormField, '2.5'), findsOneWidget);
    expect(find.textContaining('NO_TPH + WERKS must be unique'), findsOneWidget);
    expect(find.textContaining('Unique key'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // Layar memulai pemantauan koneksi (timer periodik + timeout lookup 5 dtk).
    await tester.pumpWidget(const SizedBox());
    ConnectivityService().stopMonitoring();
    await tester.pump(const Duration(seconds: 6));
  });
}
