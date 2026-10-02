import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/screens/project/geometry_editor_screen.dart';
import 'package:geoform_app/services/geometry_edit.dart';

final _t = DateTime(2026, 9, 29, 8);

/// Titik pada offset meter (timur, utara) dari acuan dekat Jakarta.
GeoPoint _m(double e, double n, {double? acc}) => GeoPoint(
      latitude: -6.2 + n / 111320,
      longitude: 106.8 + e / (111320 * 0.99414),
      accuracy: acc,
      timestamp: _t,
    );

void main() {
  final square = [
    _m(0, 0, acc: 3),
    _m(20, 0, acc: 3),
    _m(20, 20, acc: 3),
    _m(0, 20, acc: 3),
  ];

  group('GeometryEditSession', () {
    test('pilih berikut/sebelum: melingkar di poligon, mentok di garis', () {
      final poly = GeometryEditSession(GeometryType.polygon, square);
      expect(poly.selected, 0);
      poly.selectPrevious();
      expect(poly.selected, 3);
      poly.selectNext();
      expect(poly.selected, 0);

      final line = GeometryEditSession(GeometryType.line, square);
      line.selectPrevious();
      expect(line.selected, 0);
      line.select(3);
      line.selectNext();
      expect(line.selected, 3);
    });

    test('pindah → dirty, akurasi asal dipertahankan; undo → kembali', () {
      final s = GeometryEditSession(GeometryType.polygon, square);
      s.select(1);
      final target = _m(25, 2);
      expect(s.moveSelectedTo(target.latitude, target.longitude, at: _t),
          isTrue);
      expect(s.isDirty, isTrue);
      // SPEC Asumsi 7: memindah tidak "memperbaiki" akurasi titik buruk.
      expect(s.points[1].accuracy, 3);
      expect(s.original[1].accuracy, 3, reason: 'asli tak berubah');
      expect(s.undo(), isTrue);
      expect(s.isDirty, isFalse);
      expect(s.selected, 1);
    });

    test('sisip setelah terpilih; hapus menghormati jumlah minimal', () {
      final s = GeometryEditSession(GeometryType.polygon, square);
      s.select(1);
      final mid = _m(20, 10);
      s.insertAfterSelected(mid.latitude, mid.longitude, at: _t);
      expect(s.length, 5);
      expect(s.selected, 2);
      expect(s.points[2].latitude, mid.latitude);
      expect(s.points[2].accuracy, 0, reason: 'vertex sisipan = titik manual');

      expect(s.deleteSelected(), isTrue);
      expect(s.length, 4);
      s.deleteSelected();
      expect(s.length, 3);
      expect(s.canDelete, isFalse, reason: 'poligon minimal 3 titik');
      expect(s.deleteSelected(), isFalse);
      expect(s.length, 3);
    });

    test('titik (point): hanya bisa dipindah', () {
      final s = GeometryEditSession(GeometryType.point, [square.first]);
      expect(s.canInsert, isFalse);
      expect(s.canDelete, isFalse);
      expect(s.insertAfterSelected(0, 0), isFalse);
      final p = _m(3, 4);
      expect(s.moveSelectedTo(p.latitude, p.longitude), isTrue);
      expect(s.length, 1);
    });

    test('reset ke asli bisa di-undo; vertex terdekat', () {
      final s = GeometryEditSession(GeometryType.line, square);
      s.select(0);
      s.moveSelectedTo(-6.1, 106.9);
      s.reset();
      expect(s.isDirty, isFalse);
      s.undo();
      expect(s.isDirty, isTrue);

      final near = _m(19, 1);
      final fresh = GeometryEditSession(GeometryType.line, square);
      expect(fresh.nearestVertex(near.latitude, near.longitude), 1);
      final far = _m(100, 100);
      expect(fresh.nearestVertex(far.latitude, far.longitude), isNull);
    });
  });

  testWidgets('editor: pilih titik 2, geser peta, Move here, Insert, Done',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    List<GeoPoint>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.push<List<GeoPoint>>(
              context,
              MaterialPageRoute(
                builder: (_) => GeometryEditorScreen(
                  type: GeometryType.polygon,
                  points: square,
                  showBasemap: false,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Point 1 of 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Next point'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Point 2 of 4'), findsOneWidget);

    // Geser peta → crosshair tak lagi di titik 2.
    await tester.drag(find.byType(FlutterMap), const Offset(-30, 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move here'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GPS ±3.0 m'), findsOneWidget);

    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Point 3 of 5'), findsOneWidget);
    expect(find.textContaining('placed manually'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    if (find.text('Use anyway').evaluate().isNotEmpty) {
      await tester.tap(find.text('Use anyway'));
      await tester.pumpAndSettle();
    }
    expect(result, isNotNull);
    expect(result!.length, 5);
    expect(result![1].latitude, isNot(square[1].latitude));
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor: keluar dengan perubahan → konfirmasi buang',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GeometryEditorScreen(
                  type: GeometryType.line,
                  points: square,
                  showBasemap: false,
                ),
              )),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(FlutterMap), const Offset(-30, 25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move here'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard geometry changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
