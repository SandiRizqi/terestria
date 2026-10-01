import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/storage_service.dart';
import 'package:geoform_app/widgets/tracking/attribute_form_sheet.dart';

/// Sheet simpan sesi "Tracking Aktif" (T8): punya bagian Style seperti form
/// "Survey data"; style yang dipilih ikut tersimpan, tanpa diubah → default.

final _project = Project(
  id: 'pA',
  name: 'Blok A',
  description: '',
  geometryType: GeometryType.polygon,
  formFields: const [],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

final _points = [
  GeoPoint(latitude: -6.200, longitude: 106.800, timestamp: DateTime.utc(2026)),
  GeoPoint(latitude: -6.200, longitude: 106.801, timestamp: DateTime.utc(2026)),
  GeoPoint(latitude: -6.201, longitude: 106.801, timestamp: DateTime.utc(2026)),
];

class _Storage implements StorageService {
  final List<GeoData> saved = [];

  @override
  Future<void> saveGeoData(GeoData geoData) async => saved.add(geoData);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<_Storage> _openSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = _Storage();
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AttributeFormSheet(
                project: _project,
                points: _points,
                username: 'surveyor',
                storageService: storage,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return storage;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('bagian Style tampil (tertutup: "Default"), muat di 360 dp',
      (tester) async {
    await _openSheet(tester);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('style diubah → record tersimpan membawa style', (tester) async {
    final storage = await _openSheet(tester);
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    // Slider pertama polygon = opacity isi.
    tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(0.8);
    await tester.pumpAndSettle();
    expect(find.text('Custom'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(storage.saved, hasLength(1));
    expect(storage.saved.single.style?.fillOpacity, 0.8);
    expect(storage.saved.single.collectedBy, 'surveyor');
  });

  testWidgets('tanpa mengubah style → tersimpan dengan style null (default)',
      (tester) async {
    final storage = await _openSheet(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(storage.saved.single.style, isNull);
  });
}
