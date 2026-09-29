import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga regresi "peta macet saat basemap PDF": layer basemap dibangun di
/// SETIAP build (puluhan kali per detik), jadi tak boleh ada I/O berkas di
/// jalurnya. Dulu `_buildBasemapLayers` membaca seluruh overlay.png
/// (`readAsBytesSync`) + `existsSync` tiap build. Kini hanya
/// `resolvePdfOverlay` (async, sekali per ganti basemap) yang menyentuh berkas
/// overlay.
void main() {
  test('builder layer basemap tanpa dart:io / I/O sinkron', () {
    final src = File('lib/widgets/map/basemap_layers.dart').readAsStringSync();
    expect(src, isNot(contains("import 'dart:io'")));
    expect(RegExp(r'\w+Sync\(').hasMatch(src), isFalse);
  });

  test('layar peta tak lagi membaca berkas overlay PDF sendiri', () {
    for (final path in [
      'lib/screens/data_collection/data_collection_screen.dart',
      'lib/screens/navigation/navigation_screen.dart',
      'lib/screens/notifications/notification_map_screen.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('readAsBytesSync')), reason: path);
      expect(src, isNot(contains('pdfOverlayImagePath')), reason: path);
      expect(src, isNot(contains('_buildBasemapLayers')), reason: path);
    }
  });
}
