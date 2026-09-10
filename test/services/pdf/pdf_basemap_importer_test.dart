import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/basemap_model.dart';
import 'package:geoform_app/services/pdf/pdf_basemap_importer.dart';

void main() {
  group('resolveDpi', () {
    test('caps at 200 DPI on iOS', () {
      expect(PdfBasemapImporter.resolveDpi(300, isIOS: true), 200);
      expect(PdfBasemapImporter.resolveDpi(150, isIOS: true), 150);
    });

    test('uses the user value on Android', () {
      expect(PdfBasemapImporter.resolveDpi(300, isIOS: false), 300);
      expect(PdfBasemapImporter.resolveDpi(96, isIOS: false), 96);
    });
  });

  group('progressForStatus', () {
    test('maps known processing phases to progress values', () {
      expect(PdfBasemapImporter.progressForStatus('Reading metadata'), 0.3);
      expect(PdfBasemapImporter.progressForStatus('extracting coordinates'), 0.5);
      expect(PdfBasemapImporter.progressForStatus('rendering overlay'), 0.7);
      expect(PdfBasemapImporter.progressForStatus('processing complete'), 0.9);
    });

    test('defaults to 0.2 for unknown status', () {
      expect(PdfBasemapImporter.progressForStatus('starting up'), 0.2);
    });
  });

  group('buildCompletedBasemap', () {
    Basemap base() => Basemap(
          id: 'abc',
          name: 'Survey Map',
          type: BasemapType.pdf,
          urlTemplate: '',
          pdfStatus: PdfProcessingStatus.processing,
          createdAt: DateTime(2026, 1, 1),
        );

    final result = {
      'success': true,
      'overlay_image': '/data/basemaps/abc/overlay.png',
      'coordinates': {
        'min_lat': 1.0,
        'min_lon': 100.0,
        'max_lat': 2.0,
        'max_lon': 101.0,
      },
      'image_size_mb': 3.456,
      'image_width': 2048,
      'image_height': 1536,
    };

    test('maps overlay result into a completed overlay basemap', () {
      final done = PdfBasemapImporter.buildCompletedBasemap(
        base: base(),
        basemapId: 'abc',
        result: result,
        dpi: 200,
      );

      expect(done.urlTemplate, 'overlay://abc');
      expect(done.pdfOverlayImagePath, '/data/basemaps/abc/overlay.png');
      expect(done.useOverlayMode, isTrue);
      expect(done.minZoom, 10);
      expect(done.maxZoom, 22);
      expect(done.pdfMinLat, 1.0);
      expect(done.pdfMinLon, 100.0);
      expect(done.pdfMaxLat, 2.0);
      expect(done.pdfMaxLon, 101.0);
      expect(done.pdfCenterLat, 1.5);
      expect(done.pdfCenterLon, 100.5);
      expect(done.pdfStatus, PdfProcessingStatus.completed);
      expect(done.processingProgress, 1.0);
      expect(done.name, 'Survey Map'); // preserved from base
    });

    test('embeds image dimensions and DPI in the ready message', () {
      final done = PdfBasemapImporter.buildCompletedBasemap(
        base: base(),
        basemapId: 'abc',
        result: result,
        dpi: 200,
      );

      expect(done.processingMessage, contains('2048x1536'));
      expect(done.processingMessage, contains('200 DPI'));
    });
  });
}
