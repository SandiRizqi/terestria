import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/widgets/geo_data_list_item.dart';

/// Record yang gagal diunggah menampilkan alasannya di daftar data.

const _reason = 'Project "Blok A" is not accepting data right now (inactive).';

final _project = Project(
  id: 'p1',
  name: 'Blok A',
  description: '',
  geometryType: GeometryType.point,
  formFields: [
    FormFieldModel(id: 'n', label: 'Name', type: FieldType.text),
    FormFieldModel(id: 'f', label: 'Photo', type: FieldType.photo),
  ],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

GeoData _geo({bool synced = false, String? error, String? photoPath}) => GeoData(
      id: 'abcdef123456',
      projectId: 'p1',
      formData: {
        'Name': 'Pohon 7',
        if (photoPath != null)
          'Photo': [
            {'localPath': photoPath, 'name': 'a.jpg'}
          ],
      },
      points: [
        GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime(2026)),
      ],
      createdAt: DateTime(2026, 9, 30, 8),
      updatedAt: DateTime(2026, 9, 30, 8),
      isSynced: synced,
      lastSyncError: error,
    );

/// Ukuran satu tile grid detail project di HP 360 dp: 2 kolom, padding 16,
/// jarak 12, rasio 0,70 → (360 − 32 − 12) / 2 = 158.
Future<void> _pump(WidgetTester tester, GeoData geo) async {
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
            geoData: geo,
            geometryType: GeometryType.point,
            onTap: () {},
            project: _project,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('gagal diunggah → chip "Failed" + alasan, muat di tile',
      (tester) async {
    await _pump(tester, _geo(error: _reason));
    expect(find.text('Failed'), findsOneWidget);
    expect(find.textContaining('not accepting data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dengan foto: alasan tampil DI ATAS foto — tak menambah tinggi kartu '
      'dibanding tanpa alasan', (tester) async {
    final dir = Directory.systemTemp.createTempSync('item_photo');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = File('${dir.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);

    await _pump(tester, _geo(error: _reason, photoPath: photo.path));
    // Catatan: dengan font test (Ahem, lebih lebar dari font asli) tile
    // berfoto 158 dp sudah overflow 18 px SEBELUM perubahan ini (diperiksa
    // terhadap kode lama) — bukan dari alasan gagal.
    tester.takeException();

    final reason = find.textContaining('not accepting data');
    expect(reason, findsOneWidget);
    // Di dalam header foto (tinggi tetap 16:9) → tak menambah tinggi kartu.
    expect(find.ancestor(of: reason, matching: find.byType(AspectRatio)),
        findsOneWidget);
  });

  testWidgets('sudah tersinkron → alasan lama tak ditampilkan', (tester) async {
    await _pump(tester, _geo(synced: true, error: _reason));
    expect(find.textContaining('not accepting data'), findsNothing);
    expect(find.text('Synced'), findsOneWidget);
  });
}
