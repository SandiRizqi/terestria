import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

/// Model untuk menyimpan informasi georeferencing dari PDF
class PdfGeoreferencing {
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;
  final int pageWidth;
  final int pageHeight;
  
  PdfGeoreferencing({
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
    required this.pageWidth,
    required this.pageHeight,
  });
  
  /// Get center point
  double get centerLat => (minLat + maxLat) / 2;
  double get centerLon => (minLon + maxLon) / 2;
  
  /// Get extent width/height in degrees
  double get widthDegrees => (maxLon - minLon).abs();
  double get heightDegrees => (maxLat - minLat).abs();
  
  /// Calculate optimal zoom levels based on extent
  Map<String, int> calculateOptimalZoomLevels() {
    // Calculate zoom level where PDF fits nicely on screen
    // Using Web Mercator projection formula
    
    // At zoom level Z, world width = 256 * 2^Z pixels
    final desiredPixelWidth = 1000.0; // Target: PDF should be ~1000px wide
    
    // Calculate zoom based on longitude extent
    // Formula: zoom = log2(screenPixels * 360 / (extent * 256))
    final zoomFromWidth = math.log((desiredPixelWidth * 360) / (widthDegrees * 256)) / math.ln2;
    
    // For height, account for latitude (Mercator distortion)
    final desiredPixelHeight = 800.0;
    final latRad = centerLat * math.pi / 180;
    final metersPerDegreeLat = 111320.0;
    final extentMeters = heightDegrees * metersPerDegreeLat;
    
    // Mercator meters per pixel at zoom 0: 156543.03392804062
    final metersPerPixelAtZoom0 = 156543.03392804062;
    final zoomFromHeight = math.log((metersPerPixelAtZoom0 * desiredPixelHeight) / extentMeters) / math.ln2;
    
    // Use the smaller zoom to ensure full extent is visible
    int baseZoom = math.min(zoomFromWidth, zoomFromHeight).floor();
    
    // Clamp to reasonable bounds
    baseZoom = baseZoom.clamp(10, 18);
    
    // minZoom: show entire extent
    // maxZoom: allow zooming in to see details
    // baseZoom: comfortable viewing level
    final minZoom = (baseZoom - 2).clamp(8, 15);
    final maxZoom = (baseZoom + 3).clamp(12, 20);
    
    return {
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'baseZoom': baseZoom,
    };
  }
  
  /// Get bounds as List [south, west, north, east]
  List<double> get bounds => [minLat, minLon, maxLat, maxLon];
  
  @override
  String toString() {
    return 'PdfGeoreferencing(center: $centerLat,$centerLon, extent: ${widthDegrees.toStringAsFixed(4)}°x${heightDegrees.toStringAsFixed(4)}°)';
  }
}

/// Service untuk mengekstrak informasi georeferencing dari GeoPDF
class PdfGeorefExtractor {
  /// Extract georeferencing information from GeoPDF
  /// Returns null if PDF is not georeferenced
  Future<PdfGeoreferencing?> extractGeoreferencing(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        throw Exception('PDF file not found');
      }

      final bytes = await file.readAsBytes();
      final pdfString = String.fromCharCodes(bytes);
      
      // Try to extract bbox from PDF
      // GeoPDF usually contains /BBox or /GPTS arrays with coordinates
      
      // Method 1: Look for /BBox (Bounding Box)
      final bboxMatch = RegExp(r'/BBox\s*\[\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\]')
          .firstMatch(pdfString);
      
      if (bboxMatch != null) {
        // BBox format: [x1 y1 x2 y2] in PDF coordinates
        // For GeoPDF, these might be in geographic coordinates
        final x1 = double.parse(bboxMatch.group(1)!);
        final y1 = double.parse(bboxMatch.group(2)!);
        final x2 = double.parse(bboxMatch.group(3)!);
        final y2 = double.parse(bboxMatch.group(4)!);
        
        // Check if these look like geographic coordinates
        if (_isGeographicCoordinate(x1, y1) && _isGeographicCoordinate(x2, y2)) {
          return _createGeorefFromBounds(x1, y1, x2, y2, bytes);
        }
      }
      
      // Method 2: Look for /GPTS (Geographic Point Set)
      final gptsMatch = RegExp(r'/GPTS\s*\[\s*([-\d.\s]+)\]')
          .firstMatch(pdfString);
      
      if (gptsMatch != null) {
        final coords = gptsMatch.group(1)!
            .trim()
            .split(RegExp(r'\s+'))
            .map((s) => double.tryParse(s))
            .where((n) => n != null)
            .cast<double>()
            .toList();
        
        // GPTS usually contains corner coordinates
        // Format varies, but typically [lon1 lat1 lon2 lat2 lon3 lat3 lon4 lat4]
        if (coords.length >= 4) {
          final lons = <double>[];
          final lats = <double>[];
          
          for (int i = 0; i < coords.length; i += 2) {
            if (i + 1 < coords.length) {
              lons.add(coords[i]);
              lats.add(coords[i + 1]);
            }
          }
          
          if (lons.isNotEmpty && lats.isNotEmpty) {
            final minLon = lons.reduce(math.min);
            final maxLon = lons.reduce(math.max);
            final minLat = lats.reduce(math.min);
            final maxLat = lats.reduce(math.max);
            
            if (_isValidExtent(minLon, minLat, maxLon, maxLat)) {
              return _createGeorefFromBounds(minLon, minLat, maxLon, maxLat, bytes);
            }
          }
        }
      }
      
      // Method 3: Look for LGIDict (Location Geographic Information Dictionary)
      final lgiMatch = RegExp(r'/LGIDict.*?/BBox\s*\[\s*([-\d.\s]+)\]', dotAll: true)
          .firstMatch(pdfString);
      
      if (lgiMatch != null) {
        final coords = lgiMatch.group(1)!
            .trim()
            .split(RegExp(r'\s+'))
            .map((s) => double.tryParse(s))
            .where((n) => n != null)
            .cast<double>()
            .toList();
        
        if (coords.length >= 4) {
          final minLon = coords[0];
          final minLat = coords[1];
          final maxLon = coords[2];
          final maxLat = coords[3];
          
          if (_isValidExtent(minLon, minLat, maxLon, maxLat)) {
            return _createGeorefFromBounds(minLon, minLat, maxLon, maxLat, bytes);
          }
        }
      }
      
      print('⚠️ Could not extract georeferencing from PDF');
      return null;
      
    } catch (e) {
      print('❌ Error extracting georeferencing: $e');
      return null;
    }
  }
  
  /// Check if coordinate looks like a valid geographic coordinate
  bool _isGeographicCoordinate(double x, double y) {
    return x >= -180 && x <= 180 && y >= -90 && y <= 90;
  }
  
  /// Check if extent is valid
  bool _isValidExtent(double minLon, double minLat, double maxLon, double maxLat) {
    return _isGeographicCoordinate(minLon, minLat) &&
           _isGeographicCoordinate(maxLon, maxLat) &&
           minLon < maxLon &&
           minLat < maxLat;
  }
  
  /// Create georeferencing object from bounds
  PdfGeoreferencing _createGeorefFromBounds(
    double x1, double y1, double x2, double y2, Uint8List pdfBytes
  ) {
    // Get page dimensions
    final pageDimensions = _extractPageDimensions(pdfBytes);
    
    // Normalize bounds (ensure min < max)
    final minLon = math.min(x1, x2);
    final maxLon = math.max(x1, x2);
    final minLat = math.min(y1, y2);
    final maxLat = math.max(y1, y2);
    
    return PdfGeoreferencing(
      minLat: minLat,
      minLon: minLon,
      maxLat: maxLat,
      maxLon: maxLon,
      pageWidth: pageDimensions['width']!,
      pageHeight: pageDimensions['height']!,
    );
  }
  
  /// Extract page dimensions from PDF
  Map<String, int> _extractPageDimensions(Uint8List pdfBytes) {
    try {
      final pdfString = String.fromCharCodes(pdfBytes);
      
      // Look for /MediaBox [0 0 width height]
      final mediaBoxMatch = RegExp(r'/MediaBox\s*\[\s*\d+\s+\d+\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*\]')
          .firstMatch(pdfString);
      
      if (mediaBoxMatch != null) {
        final width = double.parse(mediaBoxMatch.group(1)!).toInt();
        final height = double.parse(mediaBoxMatch.group(2)!).toInt();
        return {'width': width, 'height': height};
      }
    } catch (e) {
      print('Could not extract page dimensions: $e');
    }
    
    // Default dimensions (A4 at 72 DPI)
    return {'width': 595, 'height': 842};
  }
}
