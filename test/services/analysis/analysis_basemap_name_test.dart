import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/analysis/analysis_basemap_name.dart';

void main() {
  group('analysisBasemapName', () {
    test('prefix nama project di depan judul berkas', () {
      expect(analysisBasemapName('Project Replanting', 'NDVI Blok A12'),
          'Project Replanting · NDVI Blok A12');
    });

    test('tak dobel bila judul sudah diawali nama project (abaikan kapital)',
        () {
      expect(
          analysisBasemapName(
              'Project Replanting', 'project replanting - NDVI Blok A12'),
          'project replanting - NDVI Blok A12');
    });

    test('spasi berlebih dirapikan', () {
      expect(analysisBasemapName('  Project   Replanting ', '  NDVI   A12 '),
          'Project Replanting · NDVI A12');
    });

    test('project kosong → judul saja; judul kosong → project saja', () {
      expect(analysisBasemapName(null, 'NDVI A12'), 'NDVI A12');
      expect(analysisBasemapName('   ', 'NDVI A12'), 'NDVI A12');
      expect(analysisBasemapName('Project X', '  '), 'Project X');
    });
  });
}
