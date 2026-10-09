import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/utils/project_list.dart';
import 'package:geoform_app/widgets/project/project_list_header.dart';
import 'package:geoform_app/widgets/project_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Daftar project seperti template: kartu bertag + menu aksi, chip filter,
/// dan kotak cari.

final _project = Project(
  id: 'p1',
  name: 'Palm Estate · Block C',
  description: '',
  geometryType: GeometryType.polygon,
  formFields: const [],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026, 10, 1),
  createdBy: 'dewi.s',
);

Future<void> _pumpCard(WidgetTester tester,
    {VoidCallback? onDelete, VoidCallback? onEdit}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ProjectCard(
        project: _project,
        stats: ProjectDataStats(
          total: 248,
          unsynced: 12,
          failed: 0,
          lastUpdated: DateTime(2026, 10, 9, 12, 20),
        ),
        currentUsername: 'rizky',
        now: DateTime(2026, 10, 9, 14, 30),
        onTap: () {},
        onDelete: onDelete ?? () {},
        onEdit: onEdit ?? () {},
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('kartu project', () {
    testWidgets('nama, "N records · waktu", dan tag', (tester) async {
      await _pumpCard(tester);
      expect(find.text('Palm Estate · Block C'), findsOneWidget);
      expect(find.text('248 records · 2 h ago'), findsOneWidget);
      expect(find.text('Polygon'), findsOneWidget);
      expect(find.text('12 unsynced'), findsOneWidget);
      expect(find.text('From server'), findsOneWidget);
    });

    testWidgets('menu ⋮: collectors, edit, hapus', (tester) async {
      var deletes = 0;
      await _pumpCard(tester, onDelete: () => deletes++);
      await tester.tap(find.byTooltip('Project actions'));
      await tester.pumpAndSettle();
      expect(find.text('View collectors'), findsOneWidget);
      // Bukan pembuat → edit tetap tampil, tapi ditandai hanya untuk pembuat.
      expect(find.text('Edit project'), findsOneWidget);
      expect(find.text('Only the creator can edit'), findsOneWidget);
      await tester.tap(find.text('Delete project'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
    });
  });

  group('chip filter', () {
    testWidgets('All berjumlah; memilih chip memanggil onSelected',
        (tester) async {
      ProjectListFilter? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProjectFilterChips(
            selected: ProjectListFilter.all,
            allCount: 6,
            onSelected: (f) => picked = f,
          ),
        ),
      ));
      expect(find.text('All 6'), findsOneWidget);
      await tester.tap(find.text('Unsynced'));
      expect(picked, ProjectListFilter.unsynced);
      await tester.tap(find.text('From server'));
      expect(picked, ProjectListFilter.fromServer);
    });
  });

  testWidgets('kotak cari project: ketik & hapus', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final typed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectSearchField(controller: controller, onChanged: typed.add),
      ),
    ));
    expect(find.text('Search projects...'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'palm');
    await tester.pump();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(typed, ['palm', '']);
  });
}
