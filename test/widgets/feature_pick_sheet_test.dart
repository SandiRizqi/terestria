import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/settings/app_settings.dart';
import 'package:geoform_app/widgets/map/feature_pick_sheet.dart';

/// Daftar pilihan saat satu tap mengenai beberapa feature (T10).

final _project = Project(
  id: 'p',
  name: 'Blok A',
  description: '',
  geometryType: GeometryType.polygon,
  formFields: [FormFieldModel(id: 'n', label: 'Nama', type: FieldType.text)],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

GeoData _geo(String id, String name, {LayerStyle? style}) => GeoData(
      id: id,
      projectId: 'p',
      formData: {'Nama': name},
      points: [
        for (var i = 0; i < 3; i++)
          GeoPoint(latitude: i * 0.001, longitude: 0, timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026, 9, 30, 10, 15),
      updatedAt: DateTime.utc(2026, 9, 30, 10, 15),
      collectedBy: 'rekan',
      style: style,
    );

final _features = [
  _geo('aaaaaaaa-1', 'Petak kecil'),
  _geo('bbbbbbbb-2', 'Blok besar ${'dengan nama sangat panjang ' * 3}'),
];

Future<List<GeoData?>> _openSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <GeoData?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await showFeaturePickSheet(
            context,
            features: _features,
            project: _project,
            settings: AppSettings(),
          )),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('menampilkan semua feature yang kena, sesuai urutan; muat 360 dp',
      (tester) async {
    await _openSheet(tester);
    expect(find.text('2 features here'), findsOneWidget);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles.first, 'Petak kecil');
    expect(titles.last, startsWith('Blok besar'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('memilih satu → sheet tertutup & record itu dikembalikan',
      (tester) async {
    final results = await _openSheet(tester);
    await tester.tap(find.textContaining('Blok besar'));
    await tester.pumpAndSettle();
    expect(results.single!.id, 'bbbbbbbb-2');
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('ditutup tanpa memilih → null', (tester) async {
    final results = await _openSheet(tester);
    await tester.tapAt(const Offset(180, 20)); // area gelap di luar sheet
    await tester.pumpAndSettle();
    expect(results, [null]);
  });
}
