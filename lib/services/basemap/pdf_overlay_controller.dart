import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../models/basemap_model.dart';
import '../../utils/app_logger.dart';
import 'pdf_overlay.dart';

typedef PdfOverlayResolver = Future<PdfOverlayResolution> Function(Basemap b);
typedef ImageWarmUp = Future<bool> Function(ImageProvider image);

/// Pesan untuk user bila overlay PDF tak bisa ditampilkan; null = tak perlu.
String? pdfOverlayProblemText(PdfOverlayIssue issue) => switch (issue) {
      PdfOverlayIssue.fileMissing =>
        'The PDF map image was not found. Import this PDF again from Basemaps.',
      PdfOverlayIssue.invalidBounds =>
        'The PDF map coordinates are not valid. Import this PDF again.',
      PdfOverlayIssue.notOverlay => null,
    };

const _decodeFailedText =
    'The PDF map image could not be loaded (damaged file or phone memory full).';

/// Decode [image] ke cache gambar lebih dulu (seperti precacheImage, tanpa
/// BuildContext). true bila berhasil.
Future<bool> warmUpImage(ImageProvider image) {
  final done = Completer<bool>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(bool ok) {
    if (!done.isCompleted) done.complete(ok);
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    (_, __) => finish(true),
    onError: (error, _) {
      logWarn('Decode overlay PDF gagal: $error', tag: 'BASEMAP');
      finish(false);
    },
  );
  stream.addListener(listener);
  return done.future;
}

/// Pengelola overlay PDF untuk satu layar peta. Dipakai DataCollection,
/// Navigasi, dan Notification Map agar ganti basemap berperilaku sama:
///
/// 1. overlay lama langsung dilepas dari cache gambar (memori tak menumpuk);
/// 2. overlay baru divalidasi di luar build ([resolvePdfOverlay]);
/// 3. gambar di-decode lebih dulu → [loading] true selama itu (UI menampilkan
///    indikator), durasi decode dicatat ke log `BASEMAP`;
/// 4. bila user ganti lagi sebelum selesai, hasil lama diabaikan.
class PdfOverlayController extends ChangeNotifier {
  PdfOverlayController({
    PdfOverlayResolver? resolve,
    ImageWarmUp? warmUp,
    this.onProblem,
    this.warmUpTimeout = const Duration(seconds: 30),
  })  : _resolve = resolve ?? ((b) => resolvePdfOverlay(b)),
        _warmUp = warmUp ?? warmUpImage;

  final PdfOverlayResolver _resolve;
  final ImageWarmUp _warmUp;
  final Duration warmUpTimeout;

  /// Dipanggil dengan pesan siap-tampil bila overlay gagal disiapkan.
  final void Function(String message)? onProblem;

  PdfOverlaySpec? _spec;
  bool _loading = false;
  int _generation = 0;
  bool _disposed = false;

  /// Overlay siap pakai (null = tampilkan basemap tanpa overlay PDF).
  PdfOverlaySpec? get spec => _spec;

  /// Sedang menyiapkan/men-decode overlay PDF.
  bool get loading => _loading;

  Future<void> show(Basemap? basemap) async {
    final gen = ++_generation;
    final current = _spec;
    if (basemap != null && current?.basemapId == basemap.id) return;

    _logSelected(basemap);
    // Overlay lama tak lagi ditampilkan untuk basemap baru → lepas sekarang,
    // sebelum overlay baru di-decode (puncak memori lebih rendah).
    if (current != null) unawaited(current.image.evict());

    if (basemap == null || !isPdfOverlayBasemap(basemap)) {
      _set(null, loading: false);
      return;
    }

    _set(null, loading: true);
    final res = await _resolve(basemap);
    if (_isStale(gen)) return;

    final spec = res.spec;
    if (spec == null) {
      _set(null, loading: false);
      final msg = pdfOverlayProblemText(res.issue!);
      if (msg != null) onProblem?.call(msg);
      return;
    }

    _set(spec, loading: true);
    final watch = Stopwatch()..start();
    bool ok;
    try {
      ok = await _warmUp(spec.image)
          .timeout(warmUpTimeout, onTimeout: () => false);
    } catch (_) {
      ok = false;
    }
    if (_isStale(gen)) return;

    if (!ok) {
      unawaited(spec.image.evict());
      _set(null, loading: false);
      logWarn('Overlay "${basemap.name}" (${basemap.id}) gagal di-decode '
          'setelah ${watch.elapsedMilliseconds} ms', tag: 'BASEMAP');
      onProblem?.call(_decodeFailedText);
      return;
    }

    _set(spec, loading: false);
    logInfo('Overlay "${basemap.name}" siap dalam ${watch.elapsedMilliseconds} ms'
        '${await _fileSizeText(spec)} (decode ≤$kPdfOverlayMaxDecodePx px)',
        tag: 'BASEMAP');
  }

  bool _isStale(int gen) => _disposed || gen != _generation;

  void _set(PdfOverlaySpec? spec, {required bool loading}) {
    if (_disposed) return;
    if (identical(spec, _spec) && loading == _loading) return;
    _spec = spec;
    _loading = loading;
    notifyListeners();
  }

  static void _logSelected(Basemap? b) {
    if (b == null) {
      logInfo('Basemap: default (OSM)', tag: 'BASEMAP');
      return;
    }
    final kind = isPdfOverlayBasemap(b) ? ', overlay PDF' : '';
    logInfo('Basemap: "${b.name}" (${b.id}, ${b.type.name}$kind)',
        tag: 'BASEMAP');
  }

  static Future<String> _fileSizeText(PdfOverlaySpec spec) async {
    try {
      final mb = await spec.file.length() / (1024 * 1024);
      return ', file ${mb.toStringAsFixed(1)} MB';
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
