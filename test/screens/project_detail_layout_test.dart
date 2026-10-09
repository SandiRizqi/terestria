import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/screens/project/project_detail_screen.dart';
import 'package:geoform_app/services/connectivity_service.dart';
import 'package:geoform_app/widgets/project/project_detail_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Detail project: judul, statistik, cari/filter tetap di atas (tidak ikut
/// tergulir); hanya daftar data yang bergulir dan bisa sampai ke tepi bawah
/// layar (di belakang bilah navigasi HP).

final _project = Project(
  id: 'p1',
  name: 'Blok C',
  description: '',
  geometryType: GeometryType.polygon,
  formFields: [FormFieldModel(id: 'a', label: 'Plot', type: FieldType.text)],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isSynced: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('header & cari/filter berada di luar area gulir', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: ProjectDetailScreen(project: _project)));
    await tester.pump();

    for (final header in [
      find.byType(ProjectDetailTitle),
      find.byType(ProjectStatsRow),
      find.byType(DataSearchBar),
      find.byType(RecordsHeaderRow),
    ]) {
      expect(header, findsOneWidget);
      expect(
        find.ancestor(of: header, matching: find.byType(Scrollable)),
        findsNothing,
        reason: '${header.describeMatch(Plurality.one)} harus tetap di atas',
      );
    }

    await tester.pumpWidget(const SizedBox());
    ConnectivityService().stopMonitoring();
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('tombol Select ada di baris grid/list, tidak lagi di menu ⋮',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: ProjectDetailScreen(project: _project)));
    await tester.pump();

    expect(
      find.descendant(
          of: find.byType(RecordsHeaderRow),
          matching: find.byTooltip('Select records')),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Select Records'), findsNothing);
    expect(find.text('Clear Local Data'), findsOneWidget,
        reason: 'menu ⋮ tetap terbuka berisi aksi lain');

    await tester.pumpWidget(const SizedBox());
    ConnectivityService().stopMonitoring();
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('daftar data sampai tepi bawah layar (tanpa pita kosong)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: ProjectDetailScreen(project: _project)));
    await tester.pump();

    expect(tester.getRect(find.byType(CustomScrollView)).bottom, 740);

    await tester.pumpWidget(const SizedBox());
    ConnectivityService().stopMonitoring();
    await tester.pump(const Duration(seconds: 6));
  });
}
