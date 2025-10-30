import 'pdf_validator.dart';
import 'tile_generator.dart';
import 'pdf_georef_extractor.dart';

class PdfBasemapService {
  final _validator = PdfValidator();
  final _tileGenerator = TileGenerator();
  final _georefExtractor = PdfGeorefExtractor();

  /// Validate PDF file
  Future<PdfValidationResult> validatePdf(String pdfPath) async {
    return await _validator.validate(pdfPath);
  }

  /// Extract georeferencing info from PDF
  Future<PdfGeoreferencing?> extractGeoreferencing(String pdfPath) async {
    return await _georefExtractor.extractGeoreferencing(pdfPath);
  }

  /// Generate tiles from PDF with automatic extent detection
  Future<void> generateTilesFromPdf({
    required String pdfPath,
    required String basemapId,
    required Function(double progress, String status) onProgress,
    TileGeneratorConfig? config,
  }) async {
    // Extract georeferencing first
    final georef = await extractGeoreferencing(pdfPath);
    
    if (georef == null) {
      throw Exception('PDF does not contain valid georeferencing information');
    }
    
    // Create config with georeferencing
    final finalConfig = config ?? TileGeneratorConfig(georef: georef);
    final configWithGeoref = TileGeneratorConfig(
      minZoom: finalConfig.minZoom,
      maxZoom: finalConfig.maxZoom,
      dpi: finalConfig.dpi,
      georef: georef,
    );
    
    await _tileGenerator.generateTiles(
      pdfPath: pdfPath,
      basemapId: basemapId,
      onProgress: onProgress,
      config: configWithGeoref,
    );
  }

  /// Get georeferencing for a basemap
  Future<PdfGeoreferencing?> getGeoreferencing(String pdfPath) async {
    return await _tileGenerator.getGeoreferencing(pdfPath);
  }

  /// Get base path for tiles (legacy support - now returns SQLite reference)
  @Deprecated('Tiles are now stored in SQLite cache')
  Future<String> getBasePath(String basemapId) async {
    return 'sqlite://$basemapId';
  }

  /// Delete tiles (now from SQLite cache)
  Future<void> deleteTiles(String basemapId) async {
    await _tileGenerator.deleteTiles(basemapId);
  }
}
