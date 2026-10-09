import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/mixins/map_tools_host.dart';
import 'package:geoform_app/widgets/map/tools/map_tools_controller.dart';
import 'package:geoform_app/widgets/map/tools/map_tools_panel.dart';
import 'package:geoform_app/widgets/map/tools/measure_math.dart';
import 'package:latlong2/latlong.dart';

/// Titik alat ukur bisa diedit / ditambah dengan mengetik koordinat; peta
/// bergeser ke titik itu dan hasil ukur dihitung ulang.

Widget _host(MapToolsController c, {ValueChanged<LatLng>? onFocus}) =>
    MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            right: 12,
            bottom: 12,
            child: MapToolsPanel(controller: c, onFocusPoint: onFocus),
          ),
        ]),
      ),
    );

Future<void> _type(WidgetTester tester, String lat, String lon) async {
  await tester.enterText(find.byKey(const Key('coordinateLat')), lat);
  await tester.enterText(find.byKey(const Key('coordinateLon')), lon);
  await tester.pump();
}

void main() {
  test('controller.updatePoint mengganti titik & menghitung ulang', () {
    final c = MapToolsController()..setMode(MapToolMode.distance);
    c.addPoint(const LatLng(0, 0));
    c.addPoint(const LatLng(0, 0.001));
    var notified = 0;
    c.addListener(() => notified++);

    c.updatePoint(1, const LatLng(0, 0.002));
    expect(c.points[1], const LatLng(0, 0.002));
    expect(c.lengthMeters, closeTo(haversineMeters(0, 0, 0, 0.002), 1e-6));
    expect(notified, 1);

    c.updatePoint(5, const LatLng(1, 1)); // indeks di luar → diabaikan
    expect(c.points.length, 2);
    expect(notified, 1);
  });

  testWidgets('daftar titik tampil di kartu hasil', (tester) async {
    final c = MapToolsController()..setMode(MapToolMode.distance);
    c.addPoint(const LatLng(-6.2, 106.8));
    c.addPoint(const LatLng(-6.21, 106.81));
    await tester.pumpWidget(_host(c));
    expect(find.text('-6.200000, 106.800000'), findsOneWidget);
    expect(find.text('-6.210000, 106.810000'), findsOneWidget);
  });

  testWidgets('ketuk titik → edit koordinat → titik berubah & peta bergeser',
      (tester) async {
    final c = MapToolsController()..setMode(MapToolMode.distance);
    c.addPoint(const LatLng(-6.2, 106.8));
    c.addPoint(const LatLng(-6.21, 106.81));
    LatLng? focused;
    await tester.pumpWidget(_host(c, onFocus: (p) => focused = p));

    await tester.tap(find.text('-6.210000, 106.810000'));
    await tester.pumpAndSettle();
    expect(find.text('Edit point 2'), findsOneWidget);
    await _type(tester, '-6.3', '106.9');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(c.points[1], const LatLng(-6.3, 106.9));
    expect(focused, const LatLng(-6.3, 106.9));
  });

  testWidgets('koordinat tidak valid → pesan, dialog tetap terbuka',
      (tester) async {
    final c = MapToolsController()..setMode(MapToolMode.coordinate);
    c.addPoint(const LatLng(-6.2, 106.8));
    await tester.pumpWidget(_host(c));

    await tester.tap(find.text('-6.200000, 106.800000').last);
    await tester.pumpAndSettle();
    await _type(tester, '95', '106.8');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Latitude must be between -90 and 90'), findsOneWidget);
    expect(c.points.single, const LatLng(-6.2, 106.8));
  });

  testWidgets('tempel "lat, lon" di kolom latitude mengisi keduanya',
      (tester) async {
    final c = MapToolsController()..setMode(MapToolMode.coordinate);
    await tester.pumpWidget(_host(c));

    await tester.tap(find.byKey(const Key('mapToolsAddCoordinate')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('coordinateLat')), '-6.175392, 106.827153');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(c.points.single, const LatLng(-6.175392, 106.827153));
  });

  testWidgets('tambah titik lewat koordinat di mode jarak', (tester) async {
    final c = MapToolsController()..setMode(MapToolMode.distance);
    c.addPoint(const LatLng(0, 0));
    await tester.pumpWidget(_host(c));

    await tester.tap(find.byKey(const Key('mapToolsAddCoordinate')));
    await tester.pumpAndSettle();
    expect(find.text('Add point'), findsOneWidget);
    await _type(tester, '0', '0.001');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(c.points, const [LatLng(0, 0), LatLng(0, 0.001)]);
    expect(find.textContaining('Length:'), findsOneWidget);
  });

  testWidgets('host tanpa peta terpasang: geser peta diabaikan tanpa error',
      (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key));
    key.currentState!.focusMapToolsPoint(const LatLng(-6.2, 106.8));
    expect(tester.takeException(), isNull);
  });
}

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with MapToolsHost<_Host> {
  final _map = MapController();

  @override
  MapController? get mapToolsMapController => _map;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: Stack(children: [buildMapToolsPanel()])),
      );
}
