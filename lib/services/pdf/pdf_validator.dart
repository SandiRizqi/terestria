import 'dart:io';
import 'dart:typed_data';

class PdfValidator {
  static const int maxPdfSizeMB = 200;
  static const int maxPdfSizeBytes = maxPdfSizeMB * 1024 * 1024;

  /// Validate PDF file before processing
  Future<PdfValidationResult> validate(String pdfPath) async {
    try {
      final file = File(pdfPath);
      
      // Check if file exists
      if (!await file.exists()) {
        return PdfValidationResult.error('File not found');
      }

      // Check file size
      final fileSize = await file.length();
      if (fileSize > maxPdfSizeBytes) {
        final sizeMB = (fileSize / 1024 / 1024).toStringAsFixed(2);
        return PdfValidationResult.error(
          'File size exceeds ${maxPdfSizeMB}MB limit.\nCurrent size: ${sizeMB}MB'
        );
      }

      // Read PDF
      final bytes = await file.readAsBytes();

      // Check if it's a valid PDF
      if (!_isValidPdf(bytes)) {
        return PdfValidationResult.error('Invalid PDF file format');
      }

      // Check page count
      final pageCount = _getPageCount(bytes);
      if (pageCount > 1) {
        return PdfValidationResult.error(
          'PDF contains $pageCount pages.\nOnly single-page PDFs are supported.'
        );
      }

      // Check for georeferencing info
      final hasGeoref = _checkGeoreferencing(bytes);
      if (!hasGeoref) {
        return PdfValidationResult.error(
          'PDF does not contain georeferencing information.\nPlease use a GeoPDF with spatial reference.'
        );
      }

      return PdfValidationResult.success();
    } catch (e) {
      return PdfValidationResult.error('Error reading PDF: ${e.toString()}');
    }
  }

  /// Check if file is a valid PDF
  bool _isValidPdf(Uint8List bytes) {
    if (bytes.length < 5) return false;
    
    // Check PDF header %PDF-
    final header = String.fromCharCodes(bytes.sublist(0, 5));
    return header == '%PDF-';
  }

  /// Get page count from PDF
  int _getPageCount(Uint8List bytes) {
    try {
      final pdfString = String.fromCharCodes(bytes);
      
      // Look for /Type /Page or /Type/Page
      final pageMatches = RegExp(r'/Type\s*/Page[^s]').allMatches(pdfString);
      
      // Count unique page objects
      return pageMatches.length;
    } catch (e) {
      return 1; // Default to 1 if can't determine
    }
  }

  /// Check if PDF has georeferencing information
  bool _checkGeoreferencing(Uint8List pdfBytes) {
    try {
      final pdfString = String.fromCharCodes(pdfBytes);
      
      // Look for common GeoPDF markers
      // LGIDict = Location Geographic Information Dictionary
      // GPTS = Geographic Point Set
      // VP = Viewport
      // Measure = Measurement dictionary
      return pdfString.contains('/LGIDict') || 
             pdfString.contains('/GPTS') ||
             pdfString.contains('/VP') ||
             pdfString.contains('/BBox') ||
             pdfString.contains('/Measure') ||
             pdfString.contains('/GCS'); // Geographic Coordinate System
    } catch (e) {
      return false;
    }
  }
}

class PdfValidationResult {
  final bool isValid;
  final String? error;

  PdfValidationResult._({required this.isValid, this.error});

  factory PdfValidationResult.success() => 
      PdfValidationResult._(isValid: true);
  
  factory PdfValidationResult.error(String message) => 
      PdfValidationResult._(isValid: false, error: message);
}
