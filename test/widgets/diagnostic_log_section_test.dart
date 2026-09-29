import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/widgets/settings/diagnostic_log_section.dart';

/// Aksi palsu: tanpa berkas/plugin.
class _FakeActions implements DiagnosticLogActions {
  DateTime? until;
  LogStats current = const LogStats(files: 3, bytes: 1536 * 1024);
  int shares = 0;
  int clears = 0;
  final DateTime now;
  _FakeActions(this.now);

  @override
  Future<DateTime?> loadUntil() async => until;
  @override
  Future<DateTime> enable() async =>
      until = now.add(const Duration(hours: 24));
  @override
  Future<void> disable() async => until = null;
  @override
  Future<LogStats> stats() async => current;
  @override
  Future<void> clear() async {
    clears++;
    current = const LogStats(files: 0, bytes: 0);
  }

  @override
  Future<void> share(BuildContext context) async => shares++;
}

class _ThrowingShare extends _FakeActions {
  _ThrowingShare(super.now);
  @override
  Future<void> share(BuildContext context) async =>
      throw const FileSystemException('disk penuh');
}

void main() {
  final now = DateTime(2026, 9, 29, 8);

  group('helper', () {
    test('diagnosticStatusLabel', () {
      expect(diagnosticStatusLabel(null, now), 'Mati');
      expect(diagnosticStatusLabel(now.add(const Duration(hours: 23, minutes: 30)), now),
          'Aktif · 23 jam lagi');
      expect(diagnosticStatusLabel(now.add(const Duration(minutes: 45)), now),
          'Aktif · 45 mnt lagi');
      expect(diagnosticStatusLabel(now.subtract(const Duration(minutes: 1)), now),
          'Mati');
    });

    test('formatBytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(900), '900 B');
      expect(formatBytes(350 * 1024), '350 KB');
      expect(formatBytes(1536 * 1024), '1.5 MB');
    });
  });

  Widget host(_FakeActions a) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiagnosticLogSection(actions: a, now: () => now),
          ),
        ),
      );

  testWidgets('menampilkan ukuran log & status; toggle menyalakan 24 jam',
      (tester) async {
    final a = _FakeActions(now);
    await tester.pumpWidget(host(a));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 berkas · 1.5 MB'), findsOneWidget);
    expect(find.textContaining('Mati'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('diagnostic-toggle')));
    await tester.pumpAndSettle();
    expect(a.until, now.add(const Duration(hours: 24)));
    expect(find.textContaining('Aktif · 24 jam lagi'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('diagnostic-toggle')));
    await tester.pumpAndSettle();
    expect(a.until, isNull);
  });

  testWidgets('Bagikan memanggil share', (tester) async {
    final a = _FakeActions(now);
    await tester.pumpWidget(host(a));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-logs')));
    await tester.pumpAndSettle();
    expect(a.shares, 1);
  });

  testWidgets('ekspor gagal → pesan jelas, app tak crash', (tester) async {
    final a = _ThrowingShare(now);
    await tester.pumpWidget(host(a));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-logs')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gagal membagikan log'), findsOneWidget);
  });

  testWidgets('Hapus butuh konfirmasi lalu memperbarui ukuran',
      (tester) async {
    final a = _FakeActions(now);
    await tester.pumpWidget(host(a));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clear-logs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(a.clears, 0);

    await tester.tap(find.byKey(const ValueKey('clear-logs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(a.clears, 1);
    expect(find.textContaining('0 berkas · 0 B'), findsOneWidget);
  });

  testWidgets('lebar 360 dp tanpa overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(_FakeActions(now)..until = now.add(const Duration(hours: 5))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
