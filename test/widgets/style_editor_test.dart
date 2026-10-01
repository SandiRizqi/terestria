import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/layer_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/widgets/style/style_editor.dart';

/// Editor style bersama (T6) — diekstrak dari editor Layers tanpa perubahan
/// perilaku; dipakai juga oleh bagian Style di form data (T7).

const _style = LayerStyle(
  fillColor: Color(0xFFFF9800),
  fillOpacity: 0.3,
  strokeColor: Color(0xFFE65100),
  strokeWidth: 2,
  pointSize: 12,
);

Future<List<LayerStyle>> _pump(WidgetTester tester, StyleGeometry geometry,
    {StyleLimits limits = layerStyleLimits, LayerStyle style = _style}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final changes = <LayerStyle>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: StyleEditorFields(
          style: style,
          geometry: geometry,
          limits: limits,
          onChanged: changes.add,
        ),
      ),
    ),
  ));
  return changes;
}

/// Slider terakhir pada geometri point = ukuran point.
Slider _pointSizeSlider(WidgetTester tester) =>
    tester.widgetList<Slider>(find.byType(Slider)).last;

void main() {
  test('pemetaan jenis geometri layer & project', () {
    expect(styleGeometryForLayer('Point'), StyleGeometry.point);
    expect(styleGeometryForLayer('LineString'), StyleGeometry.line);
    expect(styleGeometryForLayer('Polygon'), StyleGeometry.polygon);
    expect(styleGeometryForLayer('Mixed'), StyleGeometry.polygon);
    expect(styleGeometryForProject(GeometryType.point), StyleGeometry.point);
    expect(styleGeometryForProject(GeometryType.line), StyleGeometry.line);
    expect(styleGeometryForProject(GeometryType.polygon), StyleGeometry.polygon);
  });

  testWidgets('point: warna, opacity isi, ukuran — tanpa tebal garis & warna '
      'tepi', (tester) async {
    await _pump(tester, StyleGeometry.point);
    expect(find.text('Fill Color'), findsOneWidget);
    expect(find.text('Fill Opacity'), findsOneWidget);
    expect(find.text('Point Size'), findsOneWidget);
    expect(find.text('Line Width'), findsNothing);
    expect(find.text('Border Color'), findsNothing);
    expect(find.text('Preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('line: warna garis, opacity, tebal — tanpa ukuran point',
      (tester) async {
    await _pump(tester, StyleGeometry.line);
    expect(find.text('Line Color'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
    expect(find.text('Line Width'), findsOneWidget);
    expect(find.text('Point Size'), findsNothing);
    expect(find.text('Border Color'), findsNothing);
  });

  testWidgets('polygon: warna isi, warna tepi, opacity isi, tebal garis',
      (tester) async {
    await _pump(tester, StyleGeometry.polygon);
    expect(find.text('Fill Color'), findsOneWidget);
    expect(find.text('Border Color'), findsOneWidget);
    expect(find.text('Fill Opacity'), findsOneWidget);
    expect(find.text('Line Width'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Layers: ukuran point 4–20 (16 langkah), pratinjau seperti '
      'sebelumnya', (tester) async {
    await _pump(tester, StyleGeometry.point);
    final slider = _pointSizeSlider(tester);
    expect((slider.min, slider.max, slider.divisions), (4.0, 20.0, 16));
    // Pratinjau lama: jari-jari = pointSize (dijepit 4–18).
    expect(tester.widget<StylePreview>(find.byType(StylePreview)).pointDiameter,
        24);
  });

  testWidgets('rentang & diameter pratinjau mengikuti batas dari pemanggil',
      (tester) async {
    final limits = StyleLimits(
      minPointSize: 10,
      maxPointSize: 24,
      pointDiameter: (s) => s.pointSize * 2,
    );
    await _pump(tester, StyleGeometry.point,
        limits: limits, style: _style.copyWith(pointSize: 30));
    final slider = _pointSizeSlider(tester);
    expect((slider.min, slider.max, slider.divisions), (10.0, 24.0, 14));
    expect(slider.value, 24); // di luar rentang → dijepit, slider tetap aman
    expect(tester.widget<StylePreview>(find.byType(StylePreview)).pointDiameter,
        60);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slider memanggil onChanged dengan nilai baru', (tester) async {
    final changes = await _pump(tester, StyleGeometry.polygon);
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    sliders.first.onChanged!(0.75); // opacity
    sliders.last.onChanged!(5); // tebal garis
    expect(changes.map((s) => s.fillOpacity), [0.75, 0.3]);
    expect(changes.last.strokeWidth, 5);
  });
}
