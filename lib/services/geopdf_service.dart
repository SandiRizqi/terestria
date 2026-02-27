import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Service untuk processing GeoPDF files menggunakan native PDF renderer
/// Tidak memerlukan Python atau PyMuPDF
class GeoPdfService {
  /// Extract metadata dari PDF file
  /// Mencari georeferencing information di PDF metadata/content
  static Future<Map<String, dynamic>> extractMetadata(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        return {
          'success': false,
          'error': 'PDF file not found: $pdfPath'
        };
      }

      // Baca PDF document menggunakan printing package
      final bytes = await file.readAsBytes();
      
      // Basic metadata (printing package tidak expose page count secara direct)
      final metadata = {
        'success': true,
        'file_path': pdfPath,
        'file_size': bytes.length,
      };
      
      print('📄 PDF Metadata extracted: $metadata');
      return metadata;
    } catch (e) {
      print('❌ extractMetadata error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Extract geographic coordinates dari GeoPDF
  /// Metode: Parse PDF content untuk mencari georeferencing data
  static Future<Map<String, dynamic>> extractCoordinates(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        return {
          'success': false,
          'error': 'PDF file not found'
        };
      }

      // Baca PDF sebagai bytes untuk parsing
      final bytes = await file.readAsBytes();
      final content = String.fromCharCodes(bytes);
      
      // Cari pola koordinat dalam PDF content
      // Biasanya ada dalam format: /GPTS [minLon minLat maxLon maxLat]
      // atau /BBox [minX minY maxX maxY]
      
      Map<String, dynamic>? bounds;
      
      // Pattern 1: GPTS dengan 8 values (4 corner pairs: lon1 lat1 lon2 lat2 lon3 lat3 lon4 lat4)
      // Format GeoPDF biasanya: [lon lat lon lat lon lat lon lat]
      final gptsPattern = RegExp(
      r'/GPTS\s*\[\s*([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s*\]'
      );

      final match = gptsPattern.firstMatch(content);
      
      if (match != null) {
        final raw = [
          double.parse(match.group(1)!),
          double.parse(match.group(2)!),
          double.parse(match.group(3)!),
          double.parse(match.group(4)!),
          double.parse(match.group(5)!),
          double.parse(match.group(6)!),
          double.parse(match.group(7)!),
          double.parse(match.group(8)!),
        ];

        // GPTS bisa lat-lon atau lon-lat tergantung PDF producer.
        // Deteksi otomatis: nilai pada index 0,2,4,6 adalah kandidat field pertama.
        // Latitude valid: -90..90, Longitude valid: -180..180.
        // Jika field pertama (index 0) nilainya di luar -90..90 → pasti longitude → format lon-lat.
        // Jika field pertama nilainya di dalam -90..90 DAN field kedua (index 1) di luar -90..90
        //   → field pertama adalah lat → format lat-lon.
        // Jika keduanya dalam -90..90, gunakan magnitude: nilai yang lebih besar (abs) biasanya lon.

        final a = [raw[0], raw[2], raw[4], raw[6]]; // field pertama tiap pasang
        final b = [raw[1], raw[3], raw[5], raw[7]]; // field kedua tiap pasang

        List<double> lats;
        List<double> lons;

        final aOutOfLatRange = a.any((v) => v.abs() > 90);
        final bOutOfLatRange = b.any((v) => v.abs() > 90);

        if (aOutOfLatRange && !bOutOfLatRange) {
          // field a = lon, field b = lat  (format: lon-lat)
          lons = a;
          lats = b;
          print('📐 GPTS detected: lon-lat format (a out of lat range)');
        } else if (!aOutOfLatRange && bOutOfLatRange) {
          // field a = lat, field b = lon  (format: lat-lon)
          lats = a;
          lons = b;
          print('📐 GPTS detected: lat-lon format (b out of lat range)');
        } else {
          // Kedua field dalam range valid -90..90
          // Gunakan heuristik: field dengan rata-rata abs lebih besar → longitude
          final avgAbsA = a.map((v) => v.abs()).reduce((x, y) => x + y) / a.length;
          final avgAbsB = b.map((v) => v.abs()).reduce((x, y) => x + y) / b.length;
          if (avgAbsA > avgAbsB) {
            lons = a;
            lats = b;
            print('📐 GPTS detected: lon-lat format (heuristic avgAbs: a=$avgAbsA > b=$avgAbsB)');
          } else {
            lats = a;
            lons = b;
            print('📐 GPTS detected: lat-lon format (heuristic avgAbs: b=$avgAbsB >= a=$avgAbsA)');
          }
        }

        bounds = {
          'min_lat': lats.reduce((a, b) => a < b ? a : b),
          'max_lat': lats.reduce((a, b) => a > b ? a : b),
          'min_lon': lons.reduce((a, b) => a < b ? a : b),
          'max_lon': lons.reduce((a, b) => a > b ? a : b),
        };

        print('✅ Extracted from GPTS pattern:');
        print('   Lons: $lons');
        print('   Lats: $lats');
        print('   Bounds: $bounds');
      }
      
      // Pattern 2: BBox (Bounding Box)
      // Format BBox biasanya: [minX minY maxX maxY] atau [minLon minLat maxLon maxLat]
      if (bounds == null) {
        final bboxPattern = RegExp(r'/BBox\s*\[\s*([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s*\]');
        final bboxMatch = bboxPattern.firstMatch(content);
        
        if (bboxMatch != null) {
          final minX = double.parse(bboxMatch.group(1)!);
          final minY = double.parse(bboxMatch.group(2)!);
          final maxX = double.parse(bboxMatch.group(3)!);
          final maxY = double.parse(bboxMatch.group(4)!);
          
          // BBox format: [minLon minLat maxLon maxLat]
          bounds = {
            'min_lat': minY,
            'min_lon': minX,
            'max_lat': maxY,
            'max_lon': maxX,
          };
          
          print('✅ Extracted from BBox pattern:');
          print('   Bounds: $bounds');
        }
      }
      
      // Pattern 3: Measure objects (untuk GeoPDF) - 4 values format
      // Format Measure biasanya: [minLon minLat maxLon maxLat]
      if (bounds == null) {
        // Cari /Measure dictionary yang berisi GPTS
        final measurePattern = RegExp(r'/Measure\s*<<[^>]*?/GPTS\s*\[\s*([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s*\]');
        final measureMatch = measurePattern.firstMatch(content);
        
        if (measureMatch != null) {
          // Measure GPTS format: [minLon minLat maxLon maxLat]
          final minLon = double.parse(measureMatch.group(1)!);
          final minLat = double.parse(measureMatch.group(2)!);
          final maxLon = double.parse(measureMatch.group(3)!);
          final maxLat = double.parse(measureMatch.group(4)!);
          
          bounds = {
            'min_lat': minLat,
            'min_lon': minLon,
            'max_lat': maxLat,
            'max_lon': maxLon,
          };
          
          print('✅ Extracted from Measure pattern:');
          print('   Bounds: $bounds');
        }
      }

      if (bounds != null) {
        // VALIDATE and auto-fix if lat/lon are swapped
        // Valid ranges: latitude (-90 to 90), longitude (-180 to 180)
        var minLat = bounds['min_lat'] as double;
        var minLon = bounds['min_lon'] as double;
        var maxLat = bounds['max_lat'] as double;
        var maxLon = bounds['max_lon'] as double;
        
        // Validasi range: lat harus -90..90, lon harus -180..180
        // Juga cek kasus swap di mana lat > 90 (jelas swap)
        // ATAU keduanya valid tapi lon < lat (mis. lon=106 lat=-6 sudah benar,
        // tapi lon=-6 lat=106 artinya swap)
        bool needSwap = false;

        if (minLat.abs() > 90 || maxLat.abs() > 90) {
          // lat jelas out of range → swap
          needSwap = true;
          print('⚠️ Lat out of range (${minLat}, ${maxLat}) → swapping');
        } else if (minLon.abs() <= 90 && maxLon.abs() <= 90) {
          // Keduanya dalam -90..90: heuristik magnitude
          // nilai abs lebih besar = longitude
          final avgAbsLat = (minLat.abs() + maxLat.abs()) / 2;
          final avgAbsLon = (minLon.abs() + maxLon.abs()) / 2;
          if (avgAbsLat > avgAbsLon) {
            needSwap = true;
            print('⚠️ Lat magnitude > Lon magnitude (lat=$avgAbsLat, lon=$avgAbsLon) → swapping');
          }
        }

        if (needSwap) {
          final tempMin = minLat;
          final tempMax = maxLat;
          bounds['min_lat'] = minLon;
          bounds['max_lat'] = maxLon;
          bounds['min_lon'] = tempMin;
          bounds['max_lon'] = tempMax;
          print('✅ Coordinates swapped: $bounds');
        }
        
        print('✅ Final coordinates extracted: $bounds');
        return {
          'success': true,
          'bounds': bounds,
        };
      } else {
        print('⚠️ No georeferencing data found in PDF');
        return {
          'success': false,
          'message': 'No georeferencing data found in PDF. Please provide coordinates manually.',
        };
      }
    } catch (e) {
      print('❌ extractCoordinates error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Convert PDF page ke image menggunakan native PDF renderer
  /// Set dpi = null untuk kualitas optimal mobile (200 DPI) atau set manual
  static Future<Map<String, dynamic>> pdfToImage({
    required String pdfPath,
    required String outputPath,
    int page = 0,
    int? dpi, // null = 200 DPI (mobile optimized), atau set manual (100-400)
  }) async {
    try {
      
      final file = File(pdfPath);
      if (!await file.exists()) {
        return {
          'success': false,
          'error': 'PDF file not found'
        };
      }

      // Read PDF bytes
      final pdfBytes = await file.readAsBytes();
      
      // Render PDF page using printing package
      // Jika dpi = null, gunakan DPI moderat untuk balance kualitas & memori (200 DPI)
      // 200 DPI cukup untuk tampilan mobile & tidak membebani memori
      final pageImages = await Printing.raster(
        pdfBytes,
        pages: [page],
        dpi: dpi?.toDouble() ?? 200.0, // null = 200 DPI (optimal untuk mobile)
      );

      final pageImagesList = await pageImages.toList();
      
      if (pageImagesList.isEmpty) {
        return {
          'success': false,
          'error': 'Failed to render page $page'
        };
      }
      
      final pageImage = pageImagesList.first;
      
      // Convert to PNG
      final pngBytes = await pageImage.toPng();
      
      // Save image as PNG
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(pngBytes);

      final width = pageImage.width;
      final height = pageImage.height;

      print('✅ PDF converted to image: ${width}x$height @ ${dpi ?? 200} DPI (Mobile Optimized)');
      
      return {
        'success': true,
        'image_path': outputPath,
        'width': width,
        'height': height,
        'dpi': dpi,
      };
    } catch (e, stackTrace) {
      print('❌ pdfToImage error: $e');
      print('Stack trace: $stackTrace');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Process GeoPDF sebagai overlay image (RECOMMENDED - much faster!)
  /// Set dpi = null untuk kualitas optimal 200 DPI (RECOMMENDED untuk mobile)
  static Future<Map<String, dynamic>> processGeoPdfAsOverlay({
    required String pdfPath,
    required String outputDir,
    int? dpi, // null = 200 DPI (mobile optimized), atau set manual (100-400)
    Function(String)? onProgress,
    // Optional: Manual bounds jika auto-extract gagal
    double? manualMinLat,
    double? manualMinLon,
    double? manualMaxLat,
    double? manualMaxLon,
  }) async {
    try {
      // Create output directory
      final dir = Directory(outputDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      onProgress?.call('Extracting PDF metadata...');
      final metadata = await extractMetadata(pdfPath);
      if (metadata['success'] == false || metadata['success'] == null) {
        return metadata;
      }

      onProgress?.call('Extracting coordinates...');
      final coords = await extractCoordinates(pdfPath);
      
      Map<String, dynamic>? bounds;
      
      // Gunakan manual bounds jika disediakan
      if (manualMinLat != null && manualMinLon != null && 
          manualMaxLat != null && manualMaxLon != null) {
        print('📍 Using manual bounds');
        bounds = {
          'min_lat': manualMinLat,
          'min_lon': manualMinLon,
          'max_lat': manualMaxLat,
          'max_lon': manualMaxLon,
        };
      } else if (coords['success'] == true && coords['bounds'] != null) {
        bounds = coords['bounds'] as Map<String, dynamic>;
      }
      
      if (bounds == null) {
        return {
          'success': false,
          'error': 'No georeferencing data found. Please provide coordinates manually.',
          'message': 'This PDF does not contain georeferencing information. You need to manually specify the geographic bounds.',
        };
      }

      onProgress?.call('Converting PDF to overlay image at ${dpi ?? 200} DPI (Mobile Optimized)...');
      final overlayImage = '$outputDir/overlay.png';
      final conversion = await pdfToImage(
        pdfPath: pdfPath,
        outputPath: overlayImage,
        dpi: dpi,
      );
      
      if (conversion['success'] == false || conversion['success'] == null) {
        return conversion;
      }

      onProgress?.call('Processing complete!');

      return {
        'success': true,
        'metadata': metadata,
        'coordinates': bounds,
        'overlay_image': overlayImage,
        'image_width': conversion['width'],
        'image_height': conversion['height'],
        'message': 'GeoPDF converted to overlay image (${conversion["width"]}x${conversion["height"]} @ ${dpi ?? 200} DPI - Mobile optimized)',
        'image_size_mb': (await File(overlayImage).length()) / (1024 * 1024),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'GeoPDF processing failed: $e',
      };
    }
  }

  /// DEPRECATED: Process GeoPDF dengan tiles (gunakan processGeoPdfAsOverlay)
  

  /// Test GeoPDF service
  static Future<String> test() async {
    return '''
GeoPDF Processor (Native) is ready!
Module functions available:
  - extractMetadata (native PDF parsing)
  - extractCoordinates (regex pattern matching)
  - pdfToImage (printing package)
  - processGeoPdfAsOverlay ⚡ RECOMMENDED
  - processGeoPdf [DEPRECATED - use processGeoPdfAsOverlay]

No Python dependencies required!
''';
  }
}
