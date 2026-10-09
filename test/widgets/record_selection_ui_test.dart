import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/theme/app_theme.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/settings/app_settings.dart';
import 'package:geoform_app/widgets/geo_data_list_item.dart';
import 'package:geoform_app/widgets/project/geo_data_list_tile.dart';
import 'package:geoform_app/widgets/project/selection_app_bar.dart';

/// Mode pilih di daftar data project: checkbox di baris list & tile grid,
/// tekan lama untuk mulai memilih, dan bar pilihan.

final _project = Project(
  id: 'p1',
  name: 'Blok C',
  description: '',
  geometryType: GeometryType.point,
  formFields: [FormFieldModel(id: 'a', label: 'Plot', type: FieldType.text)],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

final _geo = GeoData(
  id: 'g1',
  projectId: 'p1',
  formData: const {'Plot': 'C-34'},
  points: [GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime(2026))],
  createdAt: DateTime(2026, 10, 8, 10, 42),
  updatedAt: DateTime(2026, 10, 8, 10, 42),
  collectedBy: 'rizky',
);

// Tile grid diuji tanpa chip pengumpul: dengan font test (Ahem, lebih lebar)
// chip tambahan membuat tile 158 dp overflow sejak sebelum perubahan ini.
final _gridGeo = GeoData(
  id: 'g1',
  projectId: 'p1',
  formData: const {'Plot': 'C-34'},
  points: _geo.points,
  createdAt: _geo.createdAt,
  updatedAt: _geo.updatedAt,
);

Future<void> _pumpTile(
  WidgetTester tester, {
  bool selectionMode = false,
  bool selected = false,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GeoDataListTile(
        geoData: _geo,
        project: _project,
        currentUsername: 'rizky',
        now: DateTime(2026, 10, 8, 14),
        settings: AppSettings(),
        selectionMode: selectionMode,
        selected: selected,
        onTap: onTap ?? () {},
        onLongPress: onLongPress,
        onEdit: () {},
        onDelete: () {},
      ),
    ),
  ));
}

Future<void> _pumpGrid(
  WidgetTester tester, {
  bool selectionMode = false,
  bool selected = false,
  VoidCallback? onLongPress,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 158,
          height: 158 / 0.70,
          child: GeoDataListItem(
            geoData: _gridGeo,
            geometryType: GeometryType.point,
            project: _project,
            selectionMode: selectionMode,
            selected: selected,
            onTap: () {},
            onLongPress: onLongPress,
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      ),
    ),
  ));
}

bool? _checkboxValue(WidgetTester tester) =>
    tester.widget<Checkbox>(find.byType(Checkbox)).value;

void main() {
  group('baris list', () {
    testWidgets('di luar mode pilih: tanpa checkbox; tekan lama → onLongPress',
        (tester) async {
      var longPresses = 0;
      await _pumpTile(tester, onLongPress: () => longPresses++);
      expect(find.byType(Checkbox), findsNothing);
      await tester.longPress(find.text('C-34'));
      expect(longPresses, 1);
    });

    testWidgets('mode pilih: checkbox sesuai status, menu ⋮ disembunyikan',
        (tester) async {
      await _pumpTile(tester, selectionMode: true, selected: true);
      expect(_checkboxValue(tester), isTrue);
      expect(find.byTooltip('Record actions'), findsNothing);

      await _pumpTile(tester, selectionMode: true, selected: false);
      expect(_checkboxValue(tester), isFalse);
    });

    testWidgets('mode pilih: ketuk baris atau checkbox → onTap', (tester) async {
      var taps = 0;
      await _pumpTile(tester, selectionMode: true, onTap: () => taps++);
      await tester.tap(find.text('C-34'));
      await tester.tap(find.byType(Checkbox));
      expect(taps, 2);
    });
  });

  group('tile grid', () {
    testWidgets('mode pilih: checkbox tampil, tombol edit/hapus disembunyikan',
        (tester) async {
      await _pumpGrid(tester);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);

      await _pumpGrid(tester, selectionMode: true, selected: true);
      expect(_checkboxValue(tester), isTrue);
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
      expect(find.byIcon(Icons.delete_rounded), findsNothing);
    });

    testWidgets('tekan lama → onLongPress', (tester) async {
      var longPresses = 0;
      await _pumpGrid(tester, onLongPress: () => longPresses++);
      // "C-34" tampil sebagai judul dan di pratinjau isian.
      await tester.longPress(find.text('C-34').first);
      expect(longPresses, 1);
    });
  });

  group('bar pilihan', () {
    Future<void> pumpBar(WidgetTester tester,
        {required int count,
        required bool allSelected,
        VoidCallback? onClose,
        VoidCallback? onToggleAll}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: SelectionAppBar(
            selectedCount: count,
            allSelected: allSelected,
            onClose: onClose ?? () {},
            onToggleAll: onToggleAll ?? () {},
          ),
        ),
      ));
    }

    testWidgets('jumlah terpilih + tombol pilih semua / tutup', (tester) async {
      var toggles = 0, closes = 0;
      await pumpBar(tester,
          count: 2,
          allSelected: false,
          onToggleAll: () => toggles++,
          onClose: () => closes++);
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Select all'));
      await tester.tap(find.byTooltip('Cancel selection'));
      expect((toggles, closes), (1, 1));
    });

    testWidgets('warna bar = hijau utama aplikasi', (tester) async {
      await pumpBar(tester, count: 1, allSelected: false);
      expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
          AppTheme.primaryGreen);
    });

    testWidgets('semua terpilih → tombol menjadi "Deselect all"', (tester) async {
      await pumpBar(tester, count: 5, allSelected: true);
      expect(find.byTooltip('Deselect all'), findsOneWidget);
      expect(find.byTooltip('Select all'), findsNothing);
    });
  });
}
