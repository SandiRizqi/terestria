import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/basemap_model.dart';
import '../../utils/app_logger.dart';

/// Sisi terpanjang maksimum saat overlay PDF di-decode. `overlay.png` bisa
/// berukuran puluhan megapiksel (A1 @ 200 DPI ≈ 4677×6622 px ≈ 124 MB RAM);
/// dibatasi agar decode cepat, hemat memori, dan tetap di bawah batas tekstur
/// GPU umum di HP.
const int kPdfOverlayMaxDecodePx = 4096;

/// Basemap PDF yang ditampilkan sebagai satu gambar overlay (bukan tile).
bool isPdfOverlayBasemap(Basemap b) =>
    b.useOverlayMode && b.pdfOverlayImagePath != null && b.hasPdfGeoreferencing;

/// Batas PDF (SW/NE); null bila tak bergeoreferensi atau batasnya rusak.
LatLngBounds? pdfBoundsOf(Basemap b) {
  if (!b.hasPdfGeoreferencing) return null;
  if (b.pdfMinLat! >= b.pdfMaxLat! || b.pdfMinLon! >= b.pdfMaxLon!) return null;
  return LatLngBounds(
    LatLng(b.pdfMinLat!, b.pdfMinLon!),
    LatLng(b.pdfMaxLat!, b.pdfMaxLon!),
  );
}

/// Pindahkan kamera ke PDF hanya bila PDF sama sekali tak terlihat. Bila sudah
/// beririsan dengan tampilan, kamera dibiarkan (user mungkin sedang bekerja di
/// area itu).
bool shouldFitToPdf({required LatLngBounds visible, required LatLngBounds pdf}) =>
    !visible.isOverlapping(pdf);

/// Overlay PDF yang SUDAH divalidasi — disiapkan sekali saat basemap berubah,
/// sehingga build peta tak pernah menyentuh berkas.
class PdfOverlaySpec {
  final String basemapId;
  final File file;
  final LatLngBounds bounds;

  /// `ResizeImage(FileImage)` — decode dibatasi [kPdfOverlayMaxDecodePx].
  final ImageProvider image;

  const PdfOverlaySpec({
    required this.basemapId,
    required this.file,
    required this.bounds,
    required this.image,
  });
}

enum PdfOverlayIssue { notOverlay, invalidBounds, fileMissing }

class PdfOverlayResolution {
  final PdfOverlaySpec? spec;
  final PdfOverlayIssue? issue;

  const PdfOverlayResolution.ready(PdfOverlaySpec this.spec) : issue = null;
  const PdfOverlayResolution.failed(PdfOverlayIssue this.issue) : spec = null;
}

/// Validasi & siapkan overlay PDF [b] (async, di luar build).
///
/// Bila path tersimpan tak ada lagi (mis. iOS memindahkan folder app setelah
/// update), coba `<documents>/basemaps/<id>/<nama berkas>` — lokasi standar
/// hasil import.
Future<PdfOverlayResolution> resolvePdfOverlay(
  Basemap b, {
  Future<Directory> Function()? documentsDir,
  int maxDecodePx = kPdfOverlayMaxDecodePx,
}) async {
  if (!isPdfOverlayBasemap(b)) {
    return const PdfOverlayResolution.failed(PdfOverlayIssue.notOverlay);
  }
  final bounds = pdfBoundsOf(b);
  if (bounds == null) {
    logWarn('Overlay "${b.name}" (${b.id}): batas PDF rusak', tag: 'BASEMAP');
    return const PdfOverlayResolution.failed(PdfOverlayIssue.invalidBounds);
  }

  var file = File(b.pdfOverlayImagePath!);
  if (!await file.exists()) {
    final relocated =
        await _relocate(b, documentsDir ?? getApplicationDocumentsDirectory);
    if (relocated == null) {
      logWarn('Overlay "${b.name}" (${b.id}): berkas gambar tak ditemukan '
          '(${b.pdfOverlayImagePath})', tag: 'BASEMAP');
      return const PdfOverlayResolution.failed(PdfOverlayIssue.fileMissing);
    }
    logInfo('Overlay "${b.name}": path basi, dipulihkan ke ${relocated.path}',
        tag: 'BASEMAP');
    file = relocated;
  }

  return PdfOverlayResolution.ready(PdfOverlaySpec(
    basemapId: b.id,
    file: file,
    bounds: bounds,
    image: ResizeImage(
      FileImage(file),
      width: maxDecodePx,
      height: maxDecodePx,
      policy: ResizeImagePolicy.fit,
    ),
  ));
}

Future<File?> _relocate(Basemap b, Future<Directory> Function() docs) async {
  try {
    final name = b.pdfOverlayImagePath!.split(RegExp(r'[\\/]')).last;
    final candidate = File('${(await docs()).path}/basemaps/${b.id}/$name');
    return await candidate.exists() ? candidate : null;
  } catch (_) {
    return null;
  }
}
