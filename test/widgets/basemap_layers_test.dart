import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/basemap_model.dart';
import 'package:geoform_app/services/basemap/pdf_overlay.dart';
import 'package:geoform_app/widgets/map/basemap_layers.dart';
import 'package:latlong2/latlong.dart';

Basemap _overlay(String id) => Basemap(
      id: id,
      name: 'Peta $id',
      type: BasemapType.pdf,
      urlTemplate: 'overlay://$id',
      pdfOverlayImagePath: '/x/$id/overlay.png',
      pdfMinLat: -6.3,
      pdfMinLon: 106.7,
      pdfMaxLat: -6.1,
      pdfMaxLon: 106.9,
    );

Basemap _sqlitePdf(String id) => Basemap(
      id: id,
      name: 'Tile $id',
      type: BasemapType.pdf,
      urlTemplate: 'sqlite://$id',
      useOverlayMode: false,
      pdfMinLat: -6.3,
      pdfMinLon: 106.7,
      pdfMaxLat: -6.1,
      pdfMaxLon: 106.9,
    );

PdfOverlaySpec _spec(String id) => PdfOverlaySpec(
      basemapId: id,
      file: File('/x/$id/overlay.png'),
      bounds: LatLngBounds(const LatLng(-6.3, 106.7), const LatLng(-6.1, 106.9)),
      image: MemoryImage(Uint8List(0)),
    );

Widget _fallback() => const SizedBox(key: ValueKey('fallback'));

void main() {
  group('buildBasemapLayers', () {
    test('overlay PDF siap → fallback + OverlayImageLayer ber-key per basemap',
        () {
      final spec = _spec('a');
      final layers =
          buildBasemapLayers(_overlay('a'), overlay: spec, fallback: _fallback);

      expect(layers.length, 2);
      expect(layers.first.key, const ValueKey('fallback'));
      final layer = layers[1] as OverlayImageLayer;
      expect(layer.key, const ValueKey('pdf-overlay-a'));
      final image = layer.overlayImages.single as OverlayImage;
      expect(image.imageProvider, same(spec.image));
      expect(image.bounds, spec.bounds);
      // PDF lama tak boleh ditampilkan di batas PDF baru selama decode.
      expect(image.gaplessPlayback, isFalse);
    });

    test('spec milik basemap lain (masih memuat) → hanya fallback', () {
      final layers = buildBasemapLayers(_overlay('b'),
          overlay: _spec('a'), fallback: _fallback);
      expect(layers.length, 1);
      expect(layers.single.key, const ValueKey('fallback'));
    });

    test('overlay belum siap / gagal → hanya fallback', () {
      final layers =
          buildBasemapLayers(_overlay('a'), overlay: null, fallback: _fallback);
      expect(layers.single.key, const ValueKey('fallback'));
    });

    test('dua PDF mode tile (sqlite://) → key beda → TileLayer dimuat ulang',
        () {
      final a = buildBasemapLayers(_sqlitePdf('a'),
              overlay: null, fallback: _fallback)
          .single as TileLayer;
      final b = buildBasemapLayers(_sqlitePdf('b'),
              overlay: null, fallback: _fallback)
          .single as TileLayer;
      // urlTemplate sama-sama '' — tanpa key, flutter_map 7 tak memuat ulang.
      expect(a.urlTemplate, '');
      expect(b.urlTemplate, '');
      expect(a.key, isNot(b.key));
    });

    test('basemap online (TMS) → urlTemplate dipakai', () {
      final osm = Basemap(
          id: 'osm',
          name: 'OSM',
          type: BasemapType.builtin,
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      final layer = buildBasemapLayers(osm, overlay: null, fallback: _fallback)
          .single as TileLayer;
      expect(layer.urlTemplate, osm.urlTemplate);
      expect(layer.key, const ValueKey('basemap-osm'));
    });
  });

  testWidgets('chip loading tampil, tak menghalangi gestur peta, muat di 360 dp',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Stack(children: [PdfOverlayLoadingChip()])),
    ));
    expect(find.text('Memuat peta PDF…'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('Memuat peta PDF…'),
            matching: find.byType(IgnorePointer)),
        findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
