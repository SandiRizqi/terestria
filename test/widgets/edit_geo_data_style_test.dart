import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/screens/project/edit_geo_data_screen.dart';
import 'package:geoform_app/services/storage_service.dart';

/// Ubah / reset style record tersimpan dari layar edit (T8): tersimpan dan
/// record jadi "belum sync" agar style ikut terunggah.

const _style = LayerStyle(
  fillColor: Color(0xFF9C27B0),
  fillOpacity: 0.6,
  strokeColor: Color(0xFF311B92),
  strokeWidth: 5,
  pointSize: 12,
);

final _project = Project(
  id: 'pA',
  name: 'Blok A',
  description: '',
  geometryType: GeometryType.polygon,
  formFields: const [],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

GeoData _geo({LayerStyle? style}) => GeoData(
      id: 'g1',
      projectId: 'pA',
      formData: const {},
      points: [
        GeoPoint(latitude: -6.200, longitude: 106.800, timestamp: DateTime.utc(2026)),
        GeoPoint(latitude: -6.200, longitude: 106.801, timestamp: DateTime.utc(2026)),
        GeoPoint(latitude: -6.201, longitude: 106.801, timestamp: DateTime.utc(2026)),
      ],
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      isSynced: true,
      style: style,
    );

class _Storage implements StorageService {
  final Map<String, GeoData> records = {};

  @override
  Future<GeoData?> getGeoDataById(String id) async => records[id];

  @override
  Future<void> saveGeoData(GeoData geoData) async =>
      records[geoData.id] = geoData;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<_Storage> _pump(WidgetTester tester, GeoData geo) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = _Storage()..records[geo.id] = geo;
  await tester.pumpWidget(MaterialApp(
    home: EditGeoDataScreen(
        geoData: geo, project: _project, storageService: storage),
  ));
  await tester.pumpAndSettle();
  return storage;
}

Future<void> _openStyle(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Style'), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text('Style'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ubah style lalu simpan → tersimpan & record belum sync',
      (tester) async {
    final storage = await _pump(tester, _geo());
    expect(find.text('Default'), findsOneWidget);
    await _openStyle(tester);
    tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(0.8);
    await tester.pump();

    await tester.tap(find.byTooltip('Save changes'));
    await tester.pumpAndSettle();

    final saved = storage.records['g1']!;
    expect(saved.style, isNotNull);
    expect(saved.style!.fillOpacity, 0.8);
    expect(saved.isSynced, isFalse);
  });

  testWidgets('"Use default" lalu simpan → style dihapus', (tester) async {
    final storage = await _pump(tester, _geo(style: _style));
    expect(find.text('Custom'), findsOneWidget);
    await _openStyle(tester);
    await tester.ensureVisible(find.text('Use default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use default'));
    await tester.pump();

    await tester.tap(find.byTooltip('Save changes'));
    await tester.pumpAndSettle();

    expect(storage.records['g1']!.style, isNull);
    expect(storage.records['g1']!.isSynced, isFalse);
  });

  testWidgets('tanpa perubahan style → style lama tetap', (tester) async {
    final storage = await _pump(tester, _geo(style: _style));
    await tester.tap(find.byTooltip('Save changes'));
    await tester.pumpAndSettle();
    expect(storage.records['g1']!.style, _style);
  });
}
