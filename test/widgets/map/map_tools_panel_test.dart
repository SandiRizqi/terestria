import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/widgets/map/tools/map_tools_controller.dart';
import 'package:geoform_app/widgets/map/tools/map_tools_panel.dart';

void main() {
  Widget host(MapToolsController c) => MaterialApp(
        home: Scaffold(
          body: Stack(children: [MapToolsPanel(controller: c)]),
        ),
      );

  testWidgets('launcher opens the tool menu and activates a mode',
      (tester) async {
    final c = MapToolsController();
    await tester.pumpWidget(host(c));

    expect(find.byKey(const Key('mapToolsLauncher')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mapToolsLauncher')));
    await tester.pumpAndSettle();

    // Mode entries visible after opening
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Area'), findsOneWidget);
    expect(find.text('Radius'), findsOneWidget);

    await tester.tap(find.text('Area'));
    await tester.pumpAndSettle();
    expect(c.mode, MapToolMode.area);
  });

  testWidgets('shows live result text for the active mode', (tester) async {
    final c = MapToolsController()..setMode(MapToolMode.coordinate);
    await tester.pumpWidget(host(c));
    // coordinate with no point → hint
    expect(find.textContaining('Tap a point'), findsOneWidget);
  });

  testWidgets('clear button empties points', (tester) async {
    final c = MapToolsController()..setMode(MapToolMode.distance);
    c.addPoint(const LatLng(0, 0));
    await tester.pumpWidget(host(c));
    await tester.tap(find.byKey(const Key('mapToolsClear')));
    await tester.pumpAndSettle();
    expect(c.points, isEmpty);
  });
}
