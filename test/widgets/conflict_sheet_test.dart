import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/sync_conflict.dart';
import 'package:geoform_app/services/sync_service.dart';
import 'package:geoform_app/widgets/sync/conflict_sheet.dart';

/// UI konflik (D2): user melihat apa yang berbeda lalu memilih versi.

final _project = Project(
  id: 'pA',
  name: 'Blok A',
  description: '',
  geometryType: GeometryType.point,
  formFields: [
    FormFieldModel(id: 'n', label: 'Name', type: FieldType.text),
    FormFieldModel(id: 'h', label: 'Height', type: FieldType.decimal),
    FormFieldModel(id: 'f', label: 'Photo', type: FieldType.photo),
  ],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

GeoPoint _pt(double lon) =>
    GeoPoint(latitude: -6.2, longitude: lon, timestamp: DateTime.utc(2026));

GeoData _mine(String id, {String name = 'Pohon 7'}) => GeoData(
      id: id,
      projectId: 'pA',
      formData: {'Name': name, 'Height': 12.5, 'Photo': [{'localPath': '/a'}]},
      points: [_pt(106.8)],
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 30, 9, 15),
    );

Map<String, dynamic> _serverJson(String id) => {
      'id': id,
      'project_id': 'pA',
      'form_data': {
        'Name': 'Pohon 7B',
        'Height': 12.5,
        'Photo': [{'serverKey': 'k1'}, {'serverKey': 'k2'}],
      },
      'points': [
        {'latitude': -6.2, 'longitude': 106.8, 'timestamp': '2026-01-01T00:00:00Z'},
        {'latitude': -6.2, 'longitude': 106.9, 'timestamp': '2026-01-01T00:00:00Z'},
      ],
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-30T02:40:00Z',
      'collected_by': 'rekan',
    };

ConflictEntry _entry(String id) => ConflictEntry(
      conflict: SyncConflict(
        geoDataId: id,
        projectId: 'pA',
        serverJson: _serverJson(id),
        detectedAt: DateTime(2026, 9, 30, 10),
      ),
      local: _mine(id, name: id == 'g1' ? 'Pohon 7' : 'Pohon 9'),
    );

void main() {
  test('ringkasan perbedaan: field, jumlah titik, jumlah foto', () {
    final changes = conflictChangeSummary(
        _mine('g1'), _entry('g1').conflict.serverVersion!, _project);
    expect(changes, [
      'Name: "Pohon 7" → "Pohon 7B"',
      'Points: 1 → 2',
      'Photo: 1 → 2 photos',
    ]);
  });

  testWidgets('banner menyebut jumlah & membuka penyelesaian', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConflictBanner(count: 2, onResolve: () => opened++),
      ),
    ));
    expect(find.text('2 records were changed on the server'), findsOneWidget);
    await tester.tap(find.text('Resolve'));
    expect(opened, 1);
  });

  testWidgets(
      'sheet: Keep mine / Use server memanggil resolve; berhasil → kartu '
      'hilang, gagal → pesan tampil', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final kept = <String>[], used = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConflictResolutionSheet(
          project: _project,
          entries: [_entry('g1'), _entry('g2')],
          keepMine: (id) async {
            kept.add(id);
            return SyncResult(success: true, message: 'ok');
          },
          useServer: (id) async {
            used.add(id);
            return SyncResult(
                success: false, message: 'Could not download the server version.');
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pohon 7'), findsOneWidget);
    expect(find.text('Pohon 9'), findsOneWidget);
    expect(find.textContaining('rekan'), findsNWidgets(2));
    expect(tester.takeException(), isNull); // muat di 360 dp

    await tester.tap(find.widgetWithText(FilledButton, 'Keep mine').first);
    await tester.pumpAndSettle();
    expect(kept, ['g1']);
    expect(find.text('Pohon 7'), findsNothing, reason: 'resolved card goes away');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Use server version'));
    await tester.pumpAndSettle();
    expect(used, ['g2']);
    expect(find.text('Could not download the server version.'), findsOneWidget);
    expect(find.text('Pohon 9'), findsOneWidget, reason: 'still unresolved');
  });
}
