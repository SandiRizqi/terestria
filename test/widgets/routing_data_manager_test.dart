import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/mixins/routing_data_manager.dart';
import 'package:geoform_app/services/routing_service.dart';

/// RoutingService palsu: hanya daftar data jalan tersimpan yang dipakai sheet.
class _FakeRouting extends Fake implements RoutingService {
  final List<DownloadedRoad> saved;
  _FakeRouting(this.saved);

  @override
  Future<List<DownloadedRoad>> listDownloadedRoads() async => saved;
}

/// Host minimal yang memakai mixin bersama — mewakili navigation & notification.
///
/// [routing] menggantikan cek platform: `flutter test` berjalan di host desktop
/// (bukan Android/iOS), sehingga tanpa ini sheet tak pernah terbuka dan yang
/// muncul adalah dialog "Navigation not available yet".
class _Host extends StatefulWidget {
  final bool routing;
  final String? activePath;
  final List<DownloadedRoad> saved;

  const _Host({
    this.routing = true,
    this.activePath,
    this.saved = const [],
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with RoutingDataManager<_Host> {
  late final RoutingService _routing = _FakeRouting(widget.saved);
  late String? _osmPath = widget.activePath;

  @override
  bool get isRoutingAvailable => widget.routing;
  @override
  RoutingService get routingService => _routing;
  @override
  String? get osmFilePath => _osmPath;
  @override
  set osmFilePath(String? v) => _osmPath = v;
  @override
  Future<void> initRoutingEngine({bool reinit = false}) async {}
  @override
  void showRoutingSnack(String m) {}

  @override
  Widget build(BuildContext c) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: showOsmManagementSheet,
            child: const Text('open'),
          ),
        ),
      );
}

Future<void> _openSheet(WidgetTester tester, _Host host) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(home: host));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shared OSM sheet exposes server download + saved roads (parity)',
      (tester) async {
    await _openSheet(tester, const _Host());

    // Fitur "tarik data jalan" dari server kini tersedia lewat mixin bersama —
    // inilah yang sebelumnya hanya ada di navigation.
    expect(find.text('Download from Server'), findsOneWidget);
    expect(find.text('Saved Roads (Offline)'), findsOneWidget);
    expect(find.text('Import .pbf File'), findsOneWidget);
  });

  testWidgets('data jalan server aktif → Update / Replace / Delete / company lain',
      (tester) async {
    const road = DownloadedRoad(
        id: 7, name: 'PT Kebun Sawit', path: '/data/roads/7.osm.pbf');
    await _openSheet(
        tester, const _Host(activePath: '/data/roads/7.osm.pbf', saved: [road]));

    expect(find.text('Active (from server)'), findsOneWidget);
    expect(find.text('PT Kebun Sawit'), findsOneWidget);
    expect(find.text('Update data'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Download another company'), findsOneWidget);
    expect(find.text('Download from Server'), findsNothing);
  });

  testWidgets('file .pbf lokal aktif → Replace File / Delete / beralih ke server',
      (tester) async {
    await _openSheet(
        tester, const _Host(activePath: '/storage/Download/jambi.osm.pbf'));

    expect(find.text('Local file'), findsOneWidget);
    expect(find.text('jambi.osm.pbf'), findsOneWidget);
    expect(find.text('Replace File'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Switch to server data'), findsOneWidget);
  });

  testWidgets('platform tanpa routing → dialog penjelasan, sheet tak dibuka',
      (tester) async {
    await _openSheet(tester, const _Host(routing: false));

    expect(find.text('Navigation not available yet'), findsOneWidget);
    expect(find.text('Download from Server'), findsNothing);
    expect(find.text('Routing Data'), findsNothing);
  });
}
