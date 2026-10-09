import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/data_view_mode_store.dart';
import 'package:geoform_app/widgets/project/project_detail_header.dart';

/// Potongan header detail project (template "Project detail · data"):
/// judul, statistik ringkas, banner sync, kotak cari + filter, jumlah record.

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
}

void main() {
  group('judul', () {
    testWidgets('nama project + pembuat & waktu ubah', (tester) async {
      await _pump(
        tester,
        ProjectDetailTitle(
          name: 'Palm Estate · Block C',
          createdBy: 'rizky.pratama',
          updatedAt: DateTime(2026, 10, 9, 12, 20),
          now: DateTime(2026, 10, 9, 14, 30),
        ),
      );
      expect(find.text('Palm Estate · Block C'), findsOneWidget);
      expect(find.text('Created by rizky.pratama · updated 2 h ago'),
          findsOneWidget);
    });

    testWidgets('tanpa pembuat → hanya waktu ubah', (tester) async {
      await _pump(
        tester,
        ProjectDetailTitle(
          name: 'Blok A',
          createdBy: null,
          updatedAt: DateTime(2026, 10, 8, 9),
          now: DateTime(2026, 10, 9, 14, 30),
        ),
      );
      expect(find.text('Updated yesterday'), findsOneWidget);
    });
  });

  testWidgets('statistik: Type / Records / Fields', (tester) async {
    await _pump(tester,
        const ProjectStatsRow(type: 'Polygon', records: 248, fields: 7));
    for (final t in ['Type', 'Polygon', 'Records', '248', 'Fields', '7']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Ringkas (satu baris label + nilai) agar ruang untuk data lebih banyak.
    expect(tester.getSize(find.byType(ProjectStatsRow)).height,
        lessThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  group('banner sync', () {
    testWidgets('record & foto tertunda; Sync dipanggil', (tester) async {
      var syncs = 0;
      await _pump(
        tester,
        SyncPendingBanner(
          unsyncedCount: 12,
          pendingPhotoCount: 3,
          projectSynced: true,
          isOnline: true,
          isSyncing: false,
          onSync: () => syncs++,
        ),
      );
      expect(find.text('12 records not synced'), findsOneWidget);
      expect(find.text('3 photos pending · Tap Sync to upload'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sync'));
      expect(syncs, 1);
    });

    testWidgets('offline → Sync nonaktif; project belum di server',
        (tester) async {
      await _pump(
        tester,
        SyncPendingBanner(
          unsyncedCount: 0,
          pendingPhotoCount: 0,
          projectSynced: false,
          isOnline: false,
          isSyncing: false,
          onSync: () {},
        ),
      );
      expect(find.text('Project not on the server yet'), findsOneWidget);
      expect(find.text('Offline — safe on this phone'), findsOneWidget);
      final sync =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sync'));
      expect(sync.onPressed, isNull);
    });
  });

  group('kotak cari + filter', () {
    testWidgets('lencana jumlah filter; tombol membuka panel filter',
        (tester) async {
      var opens = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        DataSearchBar(
          controller: controller,
          activeFilterCount: 2,
          onOpenFilters: () => opens++,
        ),
      );
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.byTooltip('Filters'));
      expect(opens, 1);
    });

    testWidgets('ketik → tombol hapus muncul dan mengosongkan teks',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        DataSearchBar(
          controller: controller,
          activeFilterCount: 0,
          onOpenFilters: () {},
        ),
      );
      expect(find.byTooltip('Clear search'), findsNothing);
      await tester.enterText(find.byType(TextField), 'C-34');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(controller.text, isEmpty);
    });
  });

  group('baris jumlah record', () {
    testWidgets('tanpa filter: total + tombol grid/list', (tester) async {
      DataViewMode? picked;
      await _pump(
        tester,
        RecordsHeaderRow(
          visibleCount: 248,
          totalCount: 248,
          hasActiveFilters: false,
          onClearFilters: () {},
          viewMode: DataViewMode.grid,
          onViewModeChanged: (m) => picked = m,
        ),
      );
      expect(find.text('248 records'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
      await tester.tap(find.byTooltip('List view'));
      expect(picked, DataViewMode.list);
    });

    testWidgets('filter aktif: "N of M" + Clear filters', (tester) async {
      var clears = 0;
      await _pump(
        tester,
        RecordsHeaderRow(
          visibleCount: 12,
          totalCount: 248,
          hasActiveFilters: true,
          onClearFilters: () => clears++,
          viewMode: DataViewMode.list,
          onViewModeChanged: (_) {},
        ),
      );
      expect(find.text('12 of 248 records'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      expect(clears, 1);
    });
  });
}
