import 'package:flutter/widgets.dart';

/// Rect asal share sheet (`sharePositionOrigin` share_plus) untuk [context]:
/// posisi widget itu di layar, dipotong ke batas layar.
///
/// share_plus di iOS/iPad menolak rect nol atau di luar layar dengan
/// `PlatformException(sharePositionOrigin: argument must be set ... must be
/// non-zero and within coordinate space of source view)`, jadi rect ini tak
/// pernah nol: widget belum ter-layout / di luar layar → titik 1×1 di tengah
/// layar. Panggil SEBELUM `await` apa pun (context bisa sudah tak terpasang).
Rect shareOriginFor(BuildContext context) {
  final screen = Offset.zero & _screenSize(context);
  final box = context.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize) {
    final rect =
        (box.localToGlobal(Offset.zero) & box.size).intersect(screen);
    if (rect.width > 0 && rect.height > 0) return rect;
  }
  return Rect.fromCenter(center: screen.center, width: 1, height: 1);
}

Size _screenSize(BuildContext context) {
  final size = MediaQuery.maybeSizeOf(context);
  if (size != null) return size;
  final view = View.of(context);
  return view.physicalSize / view.devicePixelRatio;
}
