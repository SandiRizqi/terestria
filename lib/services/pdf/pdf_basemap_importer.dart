import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../models/basemap_model.dart';
import '../geopdf_service.dart';
import '../settings_service.dart';

/// Memroses sebuah PDF georeference lokal menjadi Basemap overlay.
///
/// Logika inti diekstrak dari BasemapManagementScreen agar dapat dipakai
/// ulang oleh dua alur: pilih file lewat file-picker, dan unduh file dari
/// Analysis Report. Kelas ini tidak menyimpan Basemap maupun menyentuh UI —
/// pemanggil yang mengatur pembuatan record, update status, dan tampilan.
class PdfBasemapImporter {
  final SettingsService _settingsService;

  PdfBasemapImporter({SettingsService? settingsService})
      : _settingsService = settingsService ?? SettingsService();

  /// DPI efektif: iOS dibatasi maksimal 200 untuk mencegah masalah memori,
  /// Android memakai preferensi user apa adanya.
  static int resolveDpi(int userDpi, {required bool isIOS}) =>
      isIOS ? (userDpi > 200 ? 200 : userDpi) : userDpi;

  /// Petakan pesan progress dari GeoPdfService ke nilai 0.2–0.9.
  static double progressForStatus(String status) {
    if (status.contains('metadata')) return 0.3;
    if (status.contains('coordinates')) return 0.5;
    if (status.contains('overlay')) return 0.7;
    if (status.contains('complete')) return 0.9;
    return 0.2;
  }

  /// Bangun Basemap "completed" dari hasil overlay GeoPdf.
  ///
  /// Memakai expanded full-page bounds (`result['coordinates']`) agar overlay.png
  /// terpetakan tepat.
  static Basemap buildCompletedBasemap({
    required Basemap base,
    required String basemapId,
    required Map<String, dynamic> result,
    required int dpi,
  }) {
    final bounds = result['coordinates'] as Map<String, dynamic>;
    final minLat = (bounds['min_lat'] as num).toDouble();
    final minLon = (bounds['min_lon'] as num).toDouble();
    final maxLat = (bounds['max_lat'] as num).toDouble();
    final maxLon = (bounds['max_lon'] as num).toDouble();
    final overlayPath = result['overlay_image'] as String;
    final imageSizeMB = result['image_size_mb']?.toStringAsFixed(2) ?? '0';
    final imageWidth = result['image_width'] ?? 0;
    final imageHeight = result['image_height'] ?? 0;

    return base.copyWith(
      urlTemplate: 'overlay://$basemapId',
      pdfOverlayImagePath: overlayPath,
      useOverlayMode: true,
      minZoom: 10,
      maxZoom: 22,
      pdfMinLat: minLat,
      pdfMinLon: minLon,
      pdfMaxLat: maxLat,
      pdfMaxLon: maxLon,
      pdfCenterLat: (minLat + maxLat) / 2,
      pdfCenterLon: (minLon + maxLon) / 2,
      pdfStatus: PdfProcessingStatus.completed,
      processingProgress: 1.0,
      processingMessage:
          '✅ Ready! (${imageWidth}x$imageHeight, $imageSizeMB MB @ $dpi DPI)',
    );
  }

  /// Direktori output untuk tiles/overlay basemap (sandbox-safe di iOS).
  Future<String> resolveOutputDir(String basemapId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final outputDir = Directory('${appDir.path}/basemaps/$basemapId');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    return outputDir.path;
  }

  /// Proses [pdfPath] menjadi Basemap overlay dan kembalikan record
  /// "completed" (belum disimpan — pemanggil yang menyimpan).
  ///
  /// [base] adalah record ber-status processing (dipakai untuk id & name).
  /// Progress kasar dilaporkan lewat [onProgress]. Melempar [TimeoutException]
  /// bila melebihi 5 menit, atau [PdfBasemapImportException] untuk kegagalan
  /// lain agar pemanggil dapat menandai gagal / menampilkan pesan.
  Future<Basemap> process({
    required Basemap base,
    required String pdfPath,
    void Function(double progress, String message)? onProgress,
  }) async {
    final basemapId = base.id;
    final outputDir = await resolveOutputDir(basemapId);

    await _settingsService.initialize();
    final dpi = resolveDpi(_settingsService.settings.pdfDpi,
        isIOS: Platform.isIOS);

    final result = await GeoPdfService.processGeoPdfAsOverlay(
      pdfPath: pdfPath,
      outputDir: outputDir,
      dpi: dpi,
      onProgress: (status) =>
          onProgress?.call(progressForStatus(status), status),
    ).timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw TimeoutException(
          'PDF processing timed out. Try a smaller file or lower DPI.'),
    );

    if (result['success'] != true) {
      throw PdfBasemapImportException(
          'Overlay generation failed: ${result['message']}');
    }

    final overlayPath = result['overlay_image'] as String?;
    if (overlayPath == null || !await File(overlayPath).exists()) {
      throw PdfBasemapImportException(
          'Overlay image not found at: $overlayPath');
    }
    if (result['coordinates'] == null) {
      throw PdfBasemapImportException(
          'No coordinate data returned from overlay processor.');
    }

    return buildCompletedBasemap(
      base: base,
      basemapId: basemapId,
      result: result,
      dpi: dpi,
    );
  }
}

/// Kegagalan saat memroses PDF menjadi basemap (selain timeout).
class PdfBasemapImportException implements Exception {
  final String message;
  PdfBasemapImportException(this.message);

  @override
  String toString() => 'PdfBasemapImportException: $message';
}
