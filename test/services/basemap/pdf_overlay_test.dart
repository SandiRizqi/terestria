import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/basemap_model.dart';
import 'package:geoform_app/services/basemap/pdf_overlay.dart';
import 'package:latlong2/latlong.dart';

Basemap _pdf({
  String id = 'pdf-a',
  String? imagePath,
  double minLat = -6.3,
  double minLon = 106.7,
  double maxLat = -6.1,
  double maxLon = 106.9,
  bool overlay = true,
}) =>
    Basemap(
      id: id,
      name: 'Peta $id',
      type: BasemapType.pdf,
      urlTemplate: 'overlay://$id',
      pdfOverlayImagePath: imagePath,
      useOverlayMode: overlay,
      pdfMinLat: minLat,
      pdfMinLon: minLon,
      pdfMaxLat: maxLat,
      pdfMaxLon: maxLon,
    );

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('pdf_overlay'));
  tearDown(() => tmp.delete(recursive: true));

  File writeOverlay(String dir) {
    final f = File('$dir/overlay.png')..createSync(recursive: true);
    f.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    return f;
  }

  group('pdfBoundsOf', () {
    test('PDF bergeoreferensi → batas SW/NE', () {
      final b = pdfBoundsOf(_pdf())!;
      expect(b.south, -6.3);
      expect(b.west, 106.7);
      expect(b.north, -6.1);
      expect(b.east, 106.9);
    });

    test('min >= max → null (batas rusak)', () {
      expect(pdfBoundsOf(_pdf(minLat: -6.1, maxLat: -6.3)), isNull);
    });

    test('tanpa georeferensi → null', () {
      final b = Basemap(
          id: 'osm', name: 'OSM', type: BasemapType.builtin, urlTemplate: 'x');
      expect(pdfBoundsOf(b), isNull);
    });
  });

  group('shouldFitToPdf', () {
    final pdf = LatLngBounds(const LatLng(-6.3, 106.7), const LatLng(-6.1, 106.9));

    test('PDF di luar tampilan → pindahkan kamera', () {
      final far = LatLngBounds(const LatLng(-7.9, 112.5), const LatLng(-7.7, 112.7));
      expect(shouldFitToPdf(visible: far, pdf: pdf), isTrue);
    });

    test('PDF sudah beririsan dengan tampilan → kamera dibiarkan', () {
      final near = LatLngBounds(const LatLng(-6.2, 106.8), const LatLng(-6.0, 107.0));
      expect(shouldFitToPdf(visible: near, pdf: pdf), isFalse);
    });
  });

  group('resolvePdfOverlay', () {
    test('berkas ada → spec: batas + gambar dibatasi ≤4096 px (fit)', () async {
      final f = writeOverlay('${tmp.path}/basemaps/pdf-a');
      final res = await resolvePdfOverlay(_pdf(imagePath: f.path),
          documentsDir: () async => tmp);

      expect(res.issue, isNull);
      final spec = res.spec!;
      expect(spec.basemapId, 'pdf-a');
      expect(spec.file.path, f.path);
      expect(spec.bounds.north, -6.1);
      final image = spec.image as ResizeImage;
      expect(image.width, kPdfOverlayMaxDecodePx);
      expect(image.height, kPdfOverlayMaxDecodePx);
      expect(image.policy, ResizeImagePolicy.fit);
      expect(image.allowUpscaling, isFalse);
      expect((image.imageProvider as FileImage).file.path, f.path);
    });

    test('path lama basi (mis. iOS setelah update) → dipulihkan dari '
        '<documents>/basemaps/<id>/', () async {
      final f = writeOverlay('${tmp.path}/basemaps/pdf-a');
      final res = await resolvePdfOverlay(
        _pdf(imagePath: '/var/mobile/Containers/LAMA/Documents/basemaps/pdf-a/overlay.png'),
        documentsDir: () async => tmp,
      );
      expect(res.spec!.file.path, f.path);
    });

    test('berkas tak ada di mana pun → fileMissing', () async {
      final res = await resolvePdfOverlay(
          _pdf(imagePath: '${tmp.path}/tidak/ada.png'),
          documentsDir: () async => tmp);
      expect(res.spec, isNull);
      expect(res.issue, PdfOverlayIssue.fileMissing);
    });

    test('batas rusak → invalidBounds (tanpa I/O berkas)', () async {
      final res = await resolvePdfOverlay(
          _pdf(imagePath: '${tmp.path}/x.png', minLon: 107, maxLon: 106),
          documentsDir: () async => tmp);
      expect(res.issue, PdfOverlayIssue.invalidBounds);
    });

    test('basemap bukan overlay (tile/online) → notOverlay', () async {
      final res = await resolvePdfOverlay(_pdf(imagePath: null, overlay: false),
          documentsDir: () async => tmp);
      expect(res.issue, PdfOverlayIssue.notOverlay);
    });
  });
}
