import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/screens/data_collection/data_collection_screen.dart'
    show CollectionMode;
import 'package:geoform_app/screens/data_collection/widgets/collapsible_bottom_controls.dart';

/// Panel kontrol bawah layar koleksi: setinggi isinya. Di bawah tombol hanya
/// ada ruang bilah navigasi HP (minimal 8 dp), bukan ruang putih tambahan.

Future<void> _pump(
  WidgetTester tester, {
  required bool expanded,
  required double inset,
  GeometryType type = GeometryType.point,
  CollectionMode mode = CollectionMode.drawing,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: EdgeInsets.only(bottom: inset),
          viewPadding: EdgeInsets.only(bottom: inset),
        ),
        child: Material(
          child: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CollapsibleBottomControls(
                isExpanded: expanded,
                onToggleExpanded: () {},
                geometryType: type,
                collectionMode: mode,
                isTracking: false,
                isPaused: false,
                collectedPoints: const [],
                onToggleTracking: () {},
                onTogglePause: () {},
                onAddPoint: () {},
                onUndoPoint: () {},
                onClearPoints: () {},
              ),
            ),
          ]),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Jarak dari tepi bawah tombol terbawah ke tepi bawah panel.
double _gapBelowButtons(WidgetTester tester) {
  final panel = tester.getRect(find.byType(AnimatedContainer).first);
  final buttons = find.byType(ElevatedButton).evaluate().map(
      (e) => tester.getRect(find.byWidget(e.widget)).bottom);
  return panel.bottom - buttons.reduce((a, b) => a > b ? a : b);
}

void main() {
  for (final inset in [0.0, 48.0]) {
    final expectedGap = inset > 8 ? inset : 8.0;

    testWidgets('ringkas, bilah navigasi $inset → ruang bawah $expectedGap',
        (tester) async {
      await _pump(tester, expanded: false, inset: inset);
      expect(_gapBelowButtons(tester), closeTo(expectedGap, 0.5));
    });

    testWidgets('diperluas (gambar), bilah navigasi $inset → ruang bawah $expectedGap',
        (tester) async {
      await _pump(tester, expanded: true, inset: inset);
      expect(_gapBelowButtons(tester), closeTo(expectedGap, 0.5));
    });

    testWidgets('diperluas (tracking line), bilah navigasi $inset → ruang bawah $expectedGap',
        (tester) async {
      await _pump(tester,
          expanded: true,
          inset: inset,
          type: GeometryType.line,
          mode: CollectionMode.tracking);
      expect(_gapBelowButtons(tester), closeTo(expectedGap, 0.5));
    });
  }

  test('tinggi panel = isi + ruang bawah (dipakai layar untuk tombol peta)', () {
    expect(
        BottomControlsMetrics.height(
            expanded: false,
            type: GeometryType.point,
            mode: CollectionMode.drawing,
            bottomInset: 0),
        BottomControlsMetrics.collapsed + 8);
    expect(
        BottomControlsMetrics.height(
            expanded: true,
            type: GeometryType.line,
            mode: CollectionMode.tracking,
            bottomInset: 48),
        BottomControlsMetrics.expanded(GeometryType.line, CollectionMode.tracking) +
            48);
  });
}
