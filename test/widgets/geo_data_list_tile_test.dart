import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/settings/app_settings.dart';
import 'package:geoform_app/services/data_view_mode_store.dart';
import 'package:geoform_app/widgets/project/data_view_toggle.dart';
import 'package:geoform_app/widgets/project/geo_data_list_tile.dart';

/// Baris tampilan list data project: judul, ringkasan, status sync, dan
/// aksi edit/hapus yang sama dengan tile grid.

final _project = Project(
  id: 'p1',
  name: 'Blok C',
  description: '',
  geometryType: GeometryType.point,
  formFields: [
    FormFieldModel(id: 'a', label: 'Plot', type: FieldType.text),
    FormFieldModel(id: 'b', label: 'Condition', type: FieldType.text),
  ],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

GeoData _geo({bool synced = false, String? error}) => GeoData(
      id: 'g1',
      projectId: 'p1',
      formData: const {'Plot': 'C-34', 'Condition': 'Mature'},
      points: [
        GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime(2026)),
      ],
      createdAt: DateTime(2026, 10, 8, 10, 42),
      updatedAt: DateTime(2026, 10, 8, 10, 42),
      collectedBy: 'rizky',
      isSynced: synced,
      lastSyncError: error,
    );

Future<void> _pump(
  WidgetTester tester,
  GeoData geo, {
  VoidCallback? onTap,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GeoDataListTile(
        geoData: geo,
        project: _project,
        currentUsername: 'rizky',
        now: DateTime(2026, 10, 8, 14),
        settings: AppSettings(),
        onTap: onTap ?? () {},
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    ),
  ));
}

void main() {
  testWidgets('judul, ringkasan, dan status sync', (tester) async {
    await _pump(tester, _geo(synced: true));
    expect(find.text('C-34'), findsOneWidget);
    expect(find.text('Mature · you, 10:42'), findsOneWidget);
    expect(find.bySemanticsLabel('Synced'), findsOneWidget);
  });

  testWidgets('status lokal & gagal; alasan gagal tampil', (tester) async {
    await _pump(tester, _geo());
    expect(find.bySemanticsLabel('Not uploaded yet'), findsOneWidget);

    await _pump(tester, _geo(error: 'Project is inactive.'));
    expect(find.bySemanticsLabel('Upload failed'), findsOneWidget);
    expect(find.text('Project is inactive.'), findsOneWidget);
  });

  testWidgets('ketuk baris = buka detail', (tester) async {
    var taps = 0;
    await _pump(tester, _geo(), onTap: () => taps++);
    await tester.tap(find.text('C-34'));
    expect(taps, 1);
  });

  testWidgets('menu ⋮ berisi edit/hapus bila boleh', (tester) async {
    var edits = 0, deletes = 0;
    await _pump(tester, _geo(),
        onEdit: () => edits++, onDelete: () => deletes++);
    await tester.tap(find.byTooltip('Record actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Record actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect((edits, deletes), (1, 1));
  });

  testWidgets('tanpa izin edit/hapus → tanpa menu', (tester) async {
    await _pump(tester, _geo());
    expect(find.byTooltip('Record actions'), findsNothing);
  });

  testWidgets('tombol grid/list memanggil onChanged & menandai yang aktif',
      (tester) async {
    DataViewMode? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DataViewToggle(
          mode: DataViewMode.grid,
          onChanged: (m) => picked = m,
        ),
      ),
    ));
    expect(
      tester.getSemantics(find.byTooltip('Grid view')),
      isSemantics(label: 'Grid view', isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.byTooltip('List view')),
      isSemantics(label: 'List view', isButton: true, isSelected: false),
    );
    await tester.tap(find.byTooltip('List view'));
    expect(picked, DataViewMode.list);
  });
}
