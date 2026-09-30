import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/app_reset/local_backup_service.dart';
import 'package:geoform_app/widgets/backup/backup_actions.dart';
import 'package:share_plus/share_plus.dart';

/// Cadangan ZIP ada di folder Temp yang DIHAPUS saat logout. Bila user menutup
/// share sheet tanpa menyimpan, app tak boleh bilang cadangan sudah aman.

LocalBackupResult _backup() => LocalBackupResult(
      file: File('terestria_backup.zip'),
      projects: 1,
      records: 3,
      unsyncedRecords: 1,
      photos: 0,
      missingPhotos: const [],
      trackingSessions: 0,
      bytes: 2048,
    );

Future<bool?> _run(WidgetTester tester, ShareResultStatus status) async {
  bool? returned;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => returned = await createAndShareBackup(
            context,
            createBackup: () async => _backup(),
            share: (files, {subject, text, sharePositionOrigin}) async =>
                ShareResult('', status),
          ),
          child: const Text('backup'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('backup'));
  await tester.pumpAndSettle();
  return returned;
}

void main() {
  testWidgets('share sheet ditutup tanpa menyimpan → peringatan & false',
      (tester) async {
    expect(await _run(tester, ShareResultStatus.dismissed), isFalse);
    expect(find.textContaining('was not saved'), findsOneWidget);
  });

  testWidgets('dibagikan (iOS melapor success) → true & konfirmasi',
      (tester) async {
    expect(await _run(tester, ShareResultStatus.success), isTrue);
    expect(find.textContaining('Backup shared'), findsOneWidget);
  });

  testWidgets('hasil tak diketahui (Android) → true & minta pastikan tersimpan',
      (tester) async {
    expect(await _run(tester, ShareResultStatus.unavailable), isTrue);
    expect(find.textContaining('Make sure it was saved'), findsOneWidget);
  });
}
