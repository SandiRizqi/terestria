import 'pdf_validator.dart';
import 'tile_generator.dart';

class PdfBasemapService {
  final _validator = PdfValidator();
  final _tileGenerator = TileGenerator();

  /// Validate PDF file
  Future<PdfValidationResult> validatePdf(String pdfPath) async {
    return await _validator.validate(pdfPath);
  }

  /// Generate tiles from PDF
  Future<void> generateTilesFromPdf({
    required String pdfPath,
    required String basemapId,
    required Function(double progress, String status) onProgress,
    TileGeneratorConfig? config,
  }) async {
    await _tileGenerator.generateTiles(
      pdfPath: pdfPath,
      basemapId: basemapId,
      onProgress: onProgress,
      config: config ?? const TileGeneratorConfig(),
    );
  }

  /// Get base path for tiles
  Future<String> getBasePath(String basemapId) async {
    return await _tileGenerator.getBasePath(basemapId);
  }

  /// Get local TMS URL
  Future<String> getLocalTmsUrl(String basemapId) async {
    return await _tileGenerator.getLocalTmsUrl(basemapId);
  }

  /// Delete tiles
  Future<void> deleteTiles(String basemapId) async {
    await _tileGenerator.deleteTiles(basemapId);
  }
}
