import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/screens/project/edit_geo_data_screen.dart';
import 'package:geoform_app/services/storage_service.dart';
import 'package:geoform_app/widgets/tracking/attribute_form_sheet.dart';

/// Kombinasi unik dicek di HP saat simpan (SPEC §3.7): record lokal lain
/// dengan kunci sama memblokir simpan; edit yang tidak mengubah kunci boleh.

final _project = Project(
  id: 'pU',
  name: 'Sensus TPH',
  description: '',
  geometryType: GeometryType.polygon,
  formFields: [
    FormFieldModel(id: 'f1', label: 'WERKS', type: FieldType.text, required: true),
    FormFieldModel(id: 'f2', label: 'NO_TPH', type: FieldType.number, required: true),
    FormFieldModel(id: 'f3', label: 'NOTE', type: FieldType.text),
  ],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  uniqueFields: const ['WERKS', 'NO_TPH'],
);

final _points = [
  GeoPoint(latitude: -6.200, longitude: 106.800, timestamp: DateTime.utc(2026)),
  GeoPoint(latitude: -6.200, longitude: 106.801, timestamp: DateTime.utc(2026)),
  GeoPoint(latitude: -6.201, longitude: 106.801, timestamp: DateTime.utc(2026)),
];

GeoData _geo(String id, Map<String, dynamic> data) => GeoData(
      id: id,
      projectId: 'pU',
      formData: data,
      points: _points,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

class _Storage implements StorageService {
  final Map<String, GeoData> records = {};
  final List<GeoData> saved = [];

  @override
  Future<List<GeoData>> loadGeoData(String projectId) async =>
      records.values.where((g) => g.projectId == projectId).toList();

  @override
  Future<GeoData?> getGeoDataById(String id) async => records[id];

  @override
  Future<void> saveGeoData(GeoData geoData) async {
    saved.add(geoData);
    records[geoData.id] = geoData;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _fill(WidgetTester tester, String label, String value) async {
  await tester.enterText(find.widgetWithText(TextFormField, '$label *'), value);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sheet Tracking Aktif', () {
    Future<_Storage> open(WidgetTester tester) async {
      _phone(tester);
      final storage = _Storage()
        ..records['g1'] = _geo('g1', {'WERKS': 'A1', 'NO_TPH': 12});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AttributeFormSheet(
            project: _project,
            points: _points,
            username: 'surveyor',
            storageService: storage,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return storage;
    }

    testWidgets('kunci sama dengan record lokal lain → simpan diblokir', (tester) async {
      final storage = await open(tester);
      await _fill(tester, 'WERKS', 'a1 ');
      await _fill(tester, 'NO_TPH', '12');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(storage.saved, isEmpty);
      expect(find.text('WERKS=a1, NO_TPH=12 already exists in this project.'),
          findsOneWidget);
    });

    testWidgets('kunci lain → tersimpan', (tester) async {
      final storage = await open(tester);
      await _fill(tester, 'WERKS', 'A2');
      await _fill(tester, 'NO_TPH', '12');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(storage.saved, hasLength(1));
    });
  });

  group('layar edit record', () {
    Future<_Storage> open(WidgetTester tester, GeoData editing) async {
      _phone(tester);
      final storage = _Storage()
        ..records['g1'] = _geo('g1', {'WERKS': 'A1', 'NO_TPH': 12})
        ..records[editing.id] = editing;
      await tester.pumpWidget(MaterialApp(
        home: EditGeoDataScreen(
            geoData: editing, project: _project, storageService: storage),
      ));
      await tester.pumpAndSettle();
      return storage;
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Save changes'));
      await tester.pumpAndSettle();
    }

    testWidgets('mengubah kunci menjadi milik record lain → diblokir', (tester) async {
      final storage = await open(tester, _geo('g2', {'WERKS': 'A2', 'NO_TPH': 12}));
      await _fill(tester, 'WERKS', 'A1');
      await save(tester);
      expect(storage.saved, isEmpty);
      expect(find.textContaining('already exists in this project'), findsOneWidget);
    });

    testWidgets('duplikat lama: edit tanpa mengubah kunci tetap boleh', (tester) async {
      final storage = await open(tester, _geo('g2', {'WERKS': 'A1', 'NO_TPH': 12}));
      await tester.enterText(find.widgetWithText(TextFormField, 'NOTE'), 'catatan');
      await save(tester);
      expect(storage.saved, hasLength(1));
    });
  });
}
