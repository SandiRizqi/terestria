import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/utils/share_origin.dart';

/// share_plus di iOS menolak `sharePositionOrigin` yang nol atau di luar
/// layar: PlatformException(sharePositionOrigin: argument must be set,
/// {{0, 0}, {0, 0}} must be non-zero and within coordinate space of source
/// view). [shareOriginFor] harus selalu memberi rect valid.

const _screen = Size(390, 844); // iPhone 12–14, sama dengan laporan error

void _useScreen(WidgetTester tester) {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

bool _valid(Rect r) =>
    r.width > 0 &&
    r.height > 0 &&
    r.left >= 0 &&
    r.top >= 0 &&
    r.right <= _screen.width &&
    r.bottom <= _screen.height;

void main() {
  testWidgets('widget terlihat → rect widget itu di layar', (tester) async {
    _useScreen(tester);
    late BuildContext anchor;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 20, top: 300),
            child: Builder(builder: (c) {
              anchor = c;
              return const SizedBox(width: 200, height: 56);
            }),
          ),
        ),
      ),
    ));

    expect(shareOriginFor(anchor), const Rect.fromLTWH(20, 300, 200, 56));
  });

  testWidgets('widget menjulur keluar layar → dipotong ke batas layar',
      (tester) async {
    _useScreen(tester);
    late BuildContext anchor;
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        Positioned(
          left: -50,
          top: 800,
          child: Builder(builder: (c) {
            anchor = c;
            return const SizedBox(width: 200, height: 100);
          }),
        ),
      ]),
    ));

    final r = shareOriginFor(anchor);
    expect(r, const Rect.fromLTRB(0, 800, 150, 844));
    expect(_valid(r), isTrue);
  });

  testWidgets('widget berukuran nol / sepenuhnya di luar layar → titik 1×1 '
      'di tengah layar (tak pernah nol)', (tester) async {
    _useScreen(tester);
    late BuildContext zero, offscreen;
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        Builder(builder: (c) {
          zero = c;
          return const SizedBox.shrink();
        }),
        Positioned(
          left: 0,
          top: 2000,
          child: Builder(builder: (c) {
            offscreen = c;
            return const SizedBox(width: 100, height: 100);
          }),
        ),
      ]),
    ));

    for (final c in [zero, offscreen]) {
      final r = shareOriginFor(c);
      expect(r, Rect.fromCenter(center: const Offset(195, 422), width: 1, height: 1));
      expect(_valid(r), isTrue);
    }
  });
}
