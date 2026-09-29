import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/widgets/project_card.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';

Project _proj(String id) => Project(
      id: id,
      name: 'P$id',
      description: '',
      geometryType: GeometryType.line,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('indikator tracking muncul saat sesi aktif, hilang saat tidak',
      (tester) async {
    final p = _proj('card1');
    final mgr = TrackingSessionManager.instance;
    mgr.stop('card1'); // pastikan bersih

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectCard(
          project: p,
          onTap: () {},
          onDelete: () {},
          onEdit: () {},
        ),
      ),
    ));
    await tester.pump();
    final key = const ValueKey('tracking-active-card1');
    expect(find.byKey(key), findsNothing);

    mgr.start(p);
    await tester.pump();
    expect(find.byKey(key), findsOneWidget);

    mgr.stop('card1');
    await tester.pump();
    expect(find.byKey(key), findsNothing);
  });

  testWidgets('sesi di-pause → badge JEDA statis, bukan REC berkedip',
      (tester) async {
    final p = _proj('card2');
    final mgr = TrackingSessionManager.instance;
    mgr.stop('card2');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectCard(
          project: p,
          onTap: () {},
          onDelete: () {},
          onEdit: () {},
        ),
      ),
    ));
    mgr.start(p);
    mgr.pause('card2');
    await tester.pump();

    expect(find.byKey(const ValueKey('tracking-active-card2')), findsNothing);
    expect(find.byKey(const ValueKey('tracking-paused-card2')), findsOneWidget);

    mgr.resume('card2');
    await tester.pump();
    expect(find.byKey(const ValueKey('tracking-active-card2')), findsOneWidget);

    mgr.stop('card2');
    await tester.pump();
  });
}
