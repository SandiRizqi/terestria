import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoform_app/mixins/map_tools_host.dart';
import 'package:geoform_app/widgets/map/tools/map_tools_controller.dart';
import 'package:geoform_app/widgets/map/tools/map_tools_panel.dart';

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with MapToolsHost<_Host> {
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: Stack(children: [buildMapToolsPanel()])),
      );
}

void main() {
  testWidgets('mixin consumes taps only when a tool is active', (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key));
    final st = key.currentState!;

    // No tool active → tap not consumed.
    expect(st.handleMapToolsTap(const LatLng(0, 0)), isFalse);
    expect(st.mapToolsController.points, isEmpty);

    // Activate a tool → tap consumed and point recorded.
    st.mapToolsController.setMode(MapToolMode.distance);
    expect(st.handleMapToolsTap(const LatLng(0, 0)), isTrue);
    expect(st.mapToolsController.points.length, 1);

    // Panel wired.
    expect(find.byType(MapToolsPanel), findsOneWidget);
  });
}
