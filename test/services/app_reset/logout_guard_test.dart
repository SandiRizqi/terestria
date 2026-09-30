import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/app_reset/logout_guard.dart';
import 'package:geoform_app/services/collection_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Project _project(String id) => Project(
      id: id,
      name: 'Project $id',
      description: '',
      geometryType: GeometryType.point,
      formFields: [
        FormFieldModel(id: 'f1', label: 'Foto', type: FieldType.photo),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

GeoData _geo(String projectId, List<Map<String, dynamic>> photos) => GeoData(
      id: 'g-$projectId-${photos.length}',
      projectId: projectId,
      formData: {'Foto': photos},
      points: [
        GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime(2026)),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Map<String, dynamic> _photo(String name, {String? serverKey}) =>
    {'name': name, 'localPath': '/x/$name', 'serverKey': serverKey};

/// Buka dialog; pilihan user ditulis ke [result].
Future<void> _open(WidgetTester tester, PendingLogoutData data,
    List<LogoutChoice> result) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async =>
            result.add(await showLogoutGuardDialog(context, data)),
        child: const Text('logout'),
      ),
    ),
  ));
  await tester.tap(find.text('logout'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('countPendingLogoutData', () {
    test('menghitung project, data, foto belum upload, dan sesi tracking',
        () async {
      final a = _project('a'), b = _project('b');
      final data = await countPendingLogoutData(
        unsyncedProjects: () async => [a],
        unsyncedGeoData: () async => [
          _geo('a', [_photo('1.jpg'), _photo('2.jpg', serverKey: 'k')]),
          _geo('b', [_photo('3.jpg'), _photo('4.jpg')]),
          _geo('hilang', [_photo('5.jpg')]), // project tak ada → foto tak dihitung
        ],
        allProjects: () async => [a, b],
        liveTrackingSessions: () => 2,
      );
      expect(data.projects, 1);
      expect(data.geoData, 3);
      expect(data.photos, 3);
      expect(data.trackingSessions, 2);
      expect(data.isEmpty, isFalse);
    });

    test('draft koleksi yang tersimpan ikut dihitung (logout menghapusnya)',
        () async {
      await CollectionDraftService().save('a',
          points: [
            GeoPoint(latitude: -6.2, longitude: 106.8, timestamp: DateTime(2026))
          ],
          formData: const {'Name': 'x'});
      final data = await countPendingLogoutData(
        unsyncedProjects: () async => [],
        unsyncedGeoData: () async => [],
        allProjects: () async => [],
        liveTrackingSessions: () => 0,
      );
      expect(data.drafts, 1);
      expect(data.isEmpty, isFalse);
    });

    test('tak ada yang tertunda → isEmpty', () async {
      final data = await countPendingLogoutData(
        unsyncedProjects: () async => [],
        unsyncedGeoData: () async => [],
        allProjects: () async => [],
        liveTrackingSessions: () => 0,
      );
      expect(data.isEmpty, isTrue);
    });
  });

  group('showLogoutGuardDialog', () {
    testWidgets('tanpa data tertunda: jelaskan penghapusan; Logout → wipe',
        (tester) async {
      final result = <LogoutChoice>[];
      await _open(tester, const PendingLogoutData(), result);

      expect(find.textContaining('deleted from this phone'), findsOneWidget);
      expect(find.text('Sync first'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Log out'));
      await tester.pumpAndSettle();
      expect(result, [LogoutChoice.wipe]);
    });

    testWidgets(
        'ada data tertunda: tampilkan jumlah; Hapus nonaktif sampai DELETE '
        'diketik', (tester) async {
      final result = <LogoutChoice>[];
      await _open(
          tester,
          const PendingLogoutData(
              projects: 1, geoData: 12, photos: 30, trackingSessions: 2),
          result);

      expect(find.text('1 project'), findsOneWidget);
      expect(find.text('12 records'), findsOneWidget);
      expect(find.text('30 photos'), findsOneWidget);
      expect(find.text('2 active tracking sessions'), findsOneWidget);
      expect(tester.takeException(), isNull); // muat di 360 dp

      FilledButton wipe() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Delete & log out'));
      expect(wipe().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();
      expect(wipe().onPressed, isNull, reason: 'harus persis DELETE');

      await tester.enterText(find.byType(TextField), ' DELETE ');
      await tester.pump();
      expect(wipe().onPressed, isNotNull);

      await tester.tap(find.text('Delete & log out'));
      await tester.pumpAndSettle();
      expect(result, [LogoutChoice.wipe]);
    });

    testWidgets('hanya draft yang tertunda → tetap dialog peringatan',
        (tester) async {
      final result = <LogoutChoice>[];
      await _open(tester, const PendingLogoutData(drafts: 2), result);

      expect(find.text('2 unsaved collection drafts'), findsOneWidget);
      expect(find.text('Sync first'), findsOneWidget);
      expect(tester.takeException(), isNull); // muat di 360 dp
    });

    testWidgets('Sync first → sync; Save backup → backup; Cancel → cancel',
        (tester) async {
      final result = <LogoutChoice>[];
      const data = PendingLogoutData(geoData: 3);
      await _open(tester, data, result);
      expect(find.text('1 project'), findsNothing); // nol tak ditampilkan
      await tester.tap(find.text('Sync first'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save a backup file'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result,
          [LogoutChoice.sync, LogoutChoice.backup, LogoutChoice.cancel]);
    });
  });
}
