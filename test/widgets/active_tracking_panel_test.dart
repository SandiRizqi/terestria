import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/services/tracking/tracking_session.dart';
import 'package:geoform_app/services/tracking/tracking_session_manager.dart';
import 'package:geoform_app/widgets/tracking/active_tracking_panel.dart';

Project _proj(String id, String name) => Project(
      id: id,
      name: name,
      description: '',
      geometryType: GeometryType.line,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

GeoPoint _pt(double lon) =>
    GeoPoint(latitude: 0, longitude: lon, timestamp: DateTime(2026, 1, 1));

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final mgr = TrackingSessionManager.instance;
  void clear() {
    for (final id in mgr.sessions.keys.toList()) {
      mgr.stop(id);
    }
  }

  setUp(clear);
  tearDown(clear);

  group('helper tampilan', () {
    test('ringkasan banner per status', () {
      expect(activeTrackingBannerText(recording: 0), isNull);
      expect(activeTrackingBannerText(recording: 2), '2 recording');
      expect(activeTrackingBannerText(recording: 1, paused: 1, pending: 2),
          '1 recording · 1 paused · 2 not saved');
      expect(activeTrackingBannerText(recording: 0, pending: 1),
          '1 not saved');
    });

    test('sessionStateLabel per status', () {
      expect(sessionStateLabel(SessionState.recording), 'Recording');
      expect(sessionStateLabel(SessionState.paused), 'Paused');
      expect(sessionStateLabel(SessionState.pendingSave), 'Not saved');
    });

    test('formatElapsed', () {
      expect(formatElapsed(const Duration(seconds: 65)), '01:05');
      expect(formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });

    test('formatDistance', () {
      expect(formatDistance(850), '850 m');
      expect(formatDistance(1250), '1.25 km');
    });

    test('lastFixAgo', () {
      final now = DateTime(2026, 1, 1, 8, 0, 30);
      expect(lastFixAgo(null, now), isNull);
      expect(lastFixAgo(DateTime(2026, 1, 1, 8, 0, 28), now), 'just now');
      expect(lastFixAgo(DateTime(2026, 1, 1, 8, 0, 0), now), '30 s ago');
      expect(lastFixAgo(DateTime(2026, 1, 1, 7, 57, 30), now), '3 min ago');
    });

    test('urutan panel: merekam → jeda → belum disimpan', () {
      final m = TrackingSessionManager(maxConcurrent: 5);
      m.start(_proj('d', 'D'));
      m.finish('d');
      m.start(_proj('p', 'P'));
      m.pause('p');
      m.start(_proj('r', 'R'));
      expect(sortSessionsForPanel(m.activeSessions).map((s) => s.projectId),
          ['r', 'p', 'd']);
    });
  });

  testWidgets('banner merangkum status & hilang bila tak ada sesi',
      (tester) async {
    await tester.pumpWidget(_host(ActiveTrackingBanner(onTap: () {})));
    expect(find.textContaining('recording'), findsNothing);

    mgr.start(_proj('a', 'Jalan A'));
    mgr.start(_proj('b', 'Blok B'));
    mgr.finish('b');
    await tester.pump();
    expect(find.text('1 recording · 1 not saved'), findsOneWidget);
    expect(find.textContaining('Jalan A'), findsOneWidget);
  });

  testWidgets('panel menampilkan sesi + tombol Buka memanggil callback',
      (tester) async {
    mgr.start(_proj('a', 'Jalan A'));
    mgr.start(_proj('b', 'Blok B'));
    mgr.addPointToActiveSessions(_pt(0));

    Project? opened;
    await tester.pumpWidget(_host(ActiveTrackingPanel(
        onOpenProject: (p) => opened = p, ensureRunning: () async => true)));
    await tester.pump();

    expect(find.text('Jalan A'), findsOneWidget);
    expect(find.text('Blok B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-a')));
    await tester.pump();
    expect(opened?.id, 'a');
  });

  testWidgets('Jeda / Lanjutkan langsung dari panel', (tester) async {
    mgr.start(_proj('a', 'Jalan A'));
    var ensured = 0;
    await tester.pumpWidget(_host(ActiveTrackingPanel(
        onOpenProject: (_) {},
        ensureRunning: () async {
          ensured++;
          return true;
        })));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toggle-a')));
    await tester.pump();
    expect(mgr.sessionFor('a')!.state, SessionState.paused);
    expect(find.text('Paused'), findsOneWidget); // chip status ikut berubah

    await tester.tap(find.byKey(const ValueKey('toggle-a')));
    await tester.pump();
    expect(mgr.sessionFor('a')!.state, SessionState.recording);
    expect(ensured, 1); // GPS dipastikan hidup saat melanjutkan
  });

  testWidgets('Lanjutkan gagal (izin/service) → kembali jeda + pesan',
      (tester) async {
    mgr.start(_proj('a', 'Jalan A'));
    mgr.pause('a');
    await tester.pumpWidget(_host(ActiveTrackingPanel(
        onOpenProject: (_) {}, ensureRunning: () async => false)));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toggle-a')));
    await tester.pump();
    await tester.pump();
    expect(mgr.sessionFor('a')!.state, SessionState.paused);
    expect(find.textContaining('Could not start background GPS'), findsOneWidget);
  });

  testWidgets('draft "Belum disimpan" bisa dilanjutkan merekam',
      (tester) async {
    mgr.start(_proj('d', 'Draft D'));
    mgr.finish('d');
    await tester.pumpWidget(_host(ActiveTrackingPanel(
        onOpenProject: (_) {}, ensureRunning: () async => true)));
    await tester.pump();

    expect(find.text('Not saved'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Resume'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toggle-d')));
    await tester.pump();
    expect(mgr.sessionFor('d')!.state, SessionState.recording);
  });

  testWidgets('layar HP sempit (360 dp): kartu & banner tanpa overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    mgr.start(_proj('a', 'Nama project yang cukup panjang sekali untuk uji'));
    mgr.start(_proj('b', 'Blok B'));
    mgr.pause('b');
    mgr.start(_proj('c', 'C'));
    mgr.finish('c');
    for (var i = 0; i < 1200; i++) {
      mgr.addPointToActiveSessions(GeoPoint(
          latitude: 0,
          longitude: i * 0.01,
          timestamp: DateTime(2026, 1, 1).add(Duration(seconds: i))));
    }

    await tester.pumpWidget(_host(Column(children: [
      ActiveTrackingBanner(onTap: () {}),
      Expanded(
        child: ActiveTrackingPanel(
            onOpenProject: (_) {}, ensureRunning: () async => true),
      ),
    ])));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Buang menghentikan sesi tanpa perlu menyimpan (anti zombie)',
      (tester) async {
    mgr.start(_proj('z', 'Zombie')); // 0 titik → tak bisa disimpan sbg line

    await tester.pumpWidget(_host(ActiveTrackingPanel(
        onOpenProject: (_) {}, ensureRunning: () async => true)));
    await tester.pump();
    expect(mgr.isActive('z'), isTrue);

    await tester.tap(find.byKey(const ValueKey('discard-z')));
    await tester.pumpAndSettle(); // dialog konfirmasi
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(mgr.isActive('z'), isFalse);
  });
}
