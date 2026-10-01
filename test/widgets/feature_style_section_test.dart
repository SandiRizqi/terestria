import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/widgets/map/project_feature_layers.dart';
import 'package:geoform_app/widgets/style/feature_style_section.dart';
import 'package:geoform_app/widgets/style/style_editor.dart';

/// Bagian "Style" di form data survei (T7): tertutup menampilkan ringkasan,
/// dibuka menampilkan editor sesuai geometri project; null = default.

const _default = LayerStyle(
  fillColor: Color(0xFFFF9800),
  fillOpacity: 0.3,
  strokeColor: Color(0xFFFF9800),
  strokeWidth: 3,
  pointSize: 12,
);
const _custom = LayerStyle(
  fillColor: Color(0xFF9C27B0),
  fillOpacity: 0.6,
  strokeColor: Color(0xFF311B92),
  strokeWidth: 5,
  pointSize: 12,
);

Future<List<LayerStyle?>> _pump(WidgetTester tester,
    {LayerStyle? style,
    GeometryType type = GeometryType.polygon,
    LayerStyle defaultStyle = _default}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final changes = <LayerStyle?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: FeatureStyleSection(
          geometryType: type,
          style: style,
          defaultStyle: defaultStyle,
          onChanged: changes.add,
        ),
      ),
    ),
  ));
  return changes;
}

void main() {
  testWidgets('tertutup: judul Style + "Default", editor belum tampil',
      (tester) async {
    await _pump(tester);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.byType(StyleEditorFields), findsNothing);
  });

  testWidgets('dibuka: editor sesuai geometri project, muat di 360 dp',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    expect(find.byType(StyleEditorFields), findsOneWidget);
    expect(find.text('Border Color'), findsOneWidget); // polygon
    expect(tester.takeException(), isNull);
  });

  testWidgets('mengubah opacity dari default → style custom (nilai lain dari '
      'default)', (tester) async {
    final changes = await _pump(tester);
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(0.8);
    expect(changes, hasLength(1));
    expect(changes.single!.fillOpacity, 0.8);
    expect(changes.single!.fillColor, _default.fillColor);
    expect(changes.single!.strokeWidth, _default.strokeWidth);
  });

  testWidgets('style custom: ringkasan "Custom"; "Use default" → null',
      (tester) async {
    final changes = await _pump(tester, style: _custom);
    expect(find.text('Custom'), findsOneWidget);
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use default'));
    expect(changes, [null]);
  });

  testWidgets('point: ukuran 10–24 (14 langkah); pratinjau = diameter marker '
      'di peta', (tester) async {
    final changes = await _pump(tester, type: GeometryType.point);
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    final slider = tester.widgetList<Slider>(find.byType(Slider)).last;
    expect((slider.min, slider.max, slider.divisions), (10.0, 24.0, 14));
    // pointSize 12 → marker 24 dp di peta.
    expect(tester.widget<StylePreview>(find.byType(StylePreview)).pointDiameter,
        featurePointDiameter(_default));
    expect(featurePointDiameter(_default), 24);
    slider.onChanged!(20);
    expect(changes.single!.pointSize, 20);
  });

  testWidgets('point: Settings 24 → slider di 24, tidak dijepit ke 20',
      (tester) async {
    await _pump(tester,
        type: GeometryType.point,
        defaultStyle: _default.copyWith(pointSize: 24));
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    expect(tester.widgetList<Slider>(find.byType(Slider)).last.value, 24);
    expect(tester.widget<StylePreview>(find.byType(StylePreview)).pointDiameter,
        48);
  });

  testWidgets('masih default: tombol "Use default" nonaktif', (tester) async {
    await _pump(tester, type: GeometryType.point);
    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
        find.ancestor(of: find.text('Use default'), matching: find.byType(TextButton)));
    expect(button.onPressed, isNull);
    expect(find.text('Point Size'), findsOneWidget);
  });
}
