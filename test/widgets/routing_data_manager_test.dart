import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/mixins/routing_data_manager.dart';
import 'package:geoform_app/services/routing_service.dart';

/// Host minimal yang memakai mixin bersama — mewakili navigation & notification.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with RoutingDataManager<_Host> {
  @override
  RoutingService get routingService => RoutingService();
  @override
  String? get osmFilePath => null;
  @override
  set osmFilePath(String? v) {}
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

void main() {
  testWidgets('shared OSM sheet exposes server download + saved roads (parity)',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Fitur "tarik data jalan" dari server kini tersedia lewat mixin bersama —
    // inilah yang sebelumnya hanya ada di navigation.
    expect(find.text('Download from Server'), findsOneWidget);
    expect(find.text('Road Tersimpan (Offline)'), findsOneWidget);
    expect(find.text('Import .pbf File'), findsOneWidget);
  });
}
