import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';
import 'package:geoform_app/widgets/tracking/active_tracking_panel.dart';

Project _proj(String id, String name) => Project(
      id: id,
      name: name,
      description: '',
      geometryType: GeometryType.line,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

GeoPoint _pt(double lon) =>
    GeoPoint(latitude: 0, longitude: lon, timestamp: DateTime(2026, 1, 1));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('activeTrackingBannerText', () {
    expect(activeTrackingBannerText(0), isNull);
    expect(activeTrackingBannerText(1), 'Tracking 1 project aktif');
    expect(activeTrackingBannerText(3), 'Tracking 3 project aktif');
  });

  testWidgets('panel menampilkan sesi aktif + tombol Buka memanggil callback',
      (tester) async {
    final mgr = TrackingSessionManager.instance;
    mgr.stop('a');
    mgr.stop('b');
    mgr.start(_proj('a', 'Jalan A'));
    mgr.start(_proj('b', 'Blok B'));
    mgr.addPointToActiveSessions(_pt(0));

    Project? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActiveTrackingPanel(onOpenProject: (p) => opened = p),
      ),
    ));
    await tester.pump();

    expect(find.text('Jalan A'), findsOneWidget);
    expect(find.text('Blok B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-a')));
    await tester.pump();
    expect(opened?.id, 'a');

    mgr.stop('a');
    mgr.stop('b');
  });
}
