import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/basemap_model.dart';
import 'package:geoform_app/services/basemap/pdf_overlay.dart';
import 'package:geoform_app/services/basemap/pdf_overlay_controller.dart';
import 'package:latlong2/latlong.dart';

/// ImageProvider palsu: mencatat evict() (pelepasan dari cache gambar).
class _FakeImage extends ImageProvider<_FakeImage> {
  int evicted = 0;
  @override
  Future<_FakeImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeImage>(this);
  @override
  Future<bool> evict({
    ImageCache? cache,
    ImageConfiguration configuration = ImageConfiguration.empty,
  }) async {
    evicted++;
    return true;
  }
}

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

Basemap _tile(String id) =>
    Basemap(id: id, name: id, type: BasemapType.builtin, urlTemplate: 'https://t/{z}/{x}/{y}.png');

PdfOverlaySpec _spec(String id, _FakeImage img) => PdfOverlaySpec(
      basemapId: id,
      file: File('/x/$id/overlay.png'),
      bounds: LatLngBounds(const LatLng(-6.3, 106.7), const LatLng(-6.1, 106.9)),
      image: img,
    );

void main() {
  late Map<String, _FakeImage> images;
  late Map<String, Completer<PdfOverlayResolution>> slowResolve;
  late int resolveCalls;
  late List<String> problems;
  late Completer<bool>? warmGate;
  late bool warmResult;
  late PdfOverlayController c;

  setUp(() {
    images = {};
    slowResolve = {};
    resolveCalls = 0;
    problems = [];
    warmGate = null;
    warmResult = true;
    c = PdfOverlayController(
      resolve: (b) {
        resolveCalls++;
        final slow = slowResolve[b.id];
        if (slow != null) return slow.future;
        if (b.id == 'hilang') {
          return Future.value(
              const PdfOverlayResolution.failed(PdfOverlayIssue.fileMissing));
        }
        if (!isPdfOverlayBasemap(b)) {
          return Future.value(
              const PdfOverlayResolution.failed(PdfOverlayIssue.notOverlay));
        }
        final img = images.putIfAbsent(b.id, _FakeImage.new);
        return Future.value(PdfOverlayResolution.ready(_spec(b.id, img)));
      },
      warmUp: (_) => warmGate?.future ?? Future.value(warmResult),
      onProblem: problems.add,
    );
  });

  tearDown(() => c.dispose());

  test('show: memuat (loading) → siap; spec milik basemap itu', () async {
    warmGate = Completer<bool>();
    final done = c.show(_overlay('a'));
    await Future<void>.delayed(Duration.zero);
    expect(c.spec?.basemapId, 'a');
    expect(c.loading, isTrue);

    warmGate!.complete(true);
    await done;
    expect(c.loading, isFalse);
    expect(c.spec?.basemapId, 'a');
  });

  test('ganti A → B: gambar A dilepas dari cache (memori tak menumpuk)',
      () async {
    await c.show(_overlay('a'));
    await c.show(_overlay('b'));
    expect(c.spec?.basemapId, 'b');
    expect(images['a']!.evicted, 1);
    expect(images['b']!.evicted, 0);
  });

  test('ganti cepat A → B sebelum A selesai: hasil A yang basi diabaikan',
      () async {
    slowResolve['a'] = Completer<PdfOverlayResolution>();
    final showA = c.show(_overlay('a'));
    await c.show(_overlay('b'));
    expect(c.spec?.basemapId, 'b');

    final lateA = _FakeImage();
    slowResolve['a']!.complete(PdfOverlayResolution.ready(_spec('a', lateA)));
    await showA;
    expect(c.spec?.basemapId, 'b');
    expect(c.loading, isFalse);
  });

  test('berkas overlay hilang → tanpa overlay + pesan jelas', () async {
    await c.show(_overlay('hilang'));
    expect(c.spec, isNull);
    expect(c.loading, isFalse);
    expect(problems.single, contains('tidak ditemukan'));
  });

  test('decode gagal → tanpa overlay + pesan', () async {
    warmResult = false;
    await c.show(_overlay('a'));
    expect(c.spec, isNull);
    expect(problems.single, contains('gagal dimuat'));
  });

  test('ganti ke basemap tile → overlay lama dilepas, tanpa pesan', () async {
    await c.show(_overlay('a'));
    await c.show(_tile('osm'));
    expect(c.spec, isNull);
    expect(images['a']!.evicted, 1);
    expect(problems, isEmpty);
  });

  test('pilih basemap yang sama lagi → tak di-resolve/decode ulang', () async {
    await c.show(_overlay('a'));
    await c.show(_overlay('a'));
    expect(resolveCalls, 1);
    expect(images['a']!.evicted, 0);
  });

  testWidgets('warmUpImage: decode sungguhan — PNG valid true, rusak false',
      (tester) async {
    // PNG 1×1 transparan yang valid.
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    await tester.runAsync(() async {
      expect(await warmUpImage(MemoryImage(png)), isTrue);
      expect(await warmUpImage(MemoryImage(Uint8List.fromList([1, 2, 3]))),
          isFalse);
    });
  });

  test('notifyListeners saat status berubah', () async {
    var n = 0;
    c.addListener(() => n++);
    await c.show(_overlay('a'));
    expect(n, greaterThanOrEqualTo(2)); // loading lalu siap
  });
}
