import 'dart:io';
import 'dart:math' as math;
import 'package:printing/printing.dart';

/// Service untuk processing GeoPDF files menggunakan native PDF renderer.
/// Tidak memerlukan Python atau PyMuPDF.
class GeoPdfService {
  // ---------------------------------------------------------------------------
  // Private helpers: PDF structure parsers
  // ---------------------------------------------------------------------------

  /// Extract MediaBox page dimensions dari PDF content (dalam pts).
  /// Returns {width, height} atau null jika tidak ditemukan.
  static Map<String, double>? _extractMediaBox(String content) {
    final pattern = RegExp(
      r'/MediaBox\s*\[\s*[-.\d]+\s+[-.\d]+\s+([-.\d]+)\s+([-.\d]+)\s*\]',
    );
    final m = pattern.firstMatch(content);
    if (m == null) return null;
    return {
      'width':  double.parse(m.group(1)!),
      'height': double.parse(m.group(2)!),
    };
  }

  /// Extract Viewport /BBox dari Page dictionary.
  ///
  /// BBox = area neatline/map-frame di dalam halaman, dalam satuan pts PDF.
  /// Returns {x_left, y_bottom, x_right, y_top} dalam PDF y-up coords,
  /// atau null jika tidak ditemukan.
  ///
  /// Berlaku untuk ArcMap, ArcGIS Pro, dan produsen GeoPDF lain yang
  /// menyimpan Viewport sebagai /VP[<</Type/Viewport/BBox[...]...>>].
  static Map<String, double>? _extractViewportBBox(String content) {
    final pattern = RegExp(
      r'/VP\s*\[.*?/BBox\s*\[\s*([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s*\]',
      dotAll: true,
    );
    final m = pattern.firstMatch(content);
    if (m == null) return null;

    final v = List.generate(4, (i) => double.parse(m.group(i + 1)!));

    // Normalisasi: min/max tidak bergantung urutan sudut yang disimpan PDF
    return {
      'x_left':   math.min(v[0], v[2]),
      'x_right':  math.max(v[0], v[2]),
      'y_bottom': math.min(v[1], v[3]), // PDF y-up: y_bottom < y_top
      'y_top':    math.max(v[1], v[3]),
    };
  }

  /// Ekspansi geographic bounds dari neatline ke full-page.
  ///
  /// GPTS hanya mendefinisikan area neatline (map frame), bukan seluruh halaman.
  /// Karena overlay image adalah render full-page (termasuk margin, judul,
  /// legenda, north arrow), bounds perlu diperluas proporsional agar tidak
  /// terjadi pergeseran saat di-plot ke map.
  ///
  /// Formula: ekspansi linear berdasarkan fraksi margin terhadap halaman.
  /// Berlaku untuk semua GeoPDF dari Esri/ArcMap karena grid koordinat sejajar
  /// dengan tepi halaman (proyeksi ortogonal).
  static Map<String, double> _expandBoundsToFullPage({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required double pageWidth,   // pts
    required double pageHeight,  // pts
    required double vpXLeft,     // pts — kiri viewport
    required double vpXRight,    // pts — kanan viewport
    required double vpYBottom,   // pts — bawah viewport (PDF y-up)
    required double vpYTop,      // pts — atas viewport (PDF y-up)
  }) {
    // Fraksi posisi viewport dalam halaman (0..1)
    final leftFrac   = vpXLeft   / pageWidth;
    final rightFrac  = vpXRight  / pageWidth;
    final bottomFrac = vpYBottom / pageHeight;
    final topFrac    = vpYTop    / pageHeight;

    final vpWidthFrac  = rightFrac - leftFrac;
    final vpHeightFrac = topFrac   - bottomFrac;

    // Derajat per satuan halaman (linear interpolation)
    final lonPerPageUnit = (maxLon - minLon) / vpWidthFrac;
    final latPerPageUnit = (maxLat - minLat) / vpHeightFrac;

    // Ekspansi ke tepi halaman
    final fullMinLon = minLon - leftFrac          * lonPerPageUnit;
    final fullMaxLon = maxLon + (1.0 - rightFrac) * lonPerPageUnit;
    final fullMinLat = minLat - bottomFrac         * latPerPageUnit;
    final fullMaxLat = maxLat + (1.0 - topFrac)   * latPerPageUnit;

    print('🗺️ Bounds expanded neatline → full-page:');
    print('   Neatline → lat:[$minLat..$maxLat]  lon:[$minLon..$maxLon]');
    print('   FullPage → lat:[${fullMinLat.toStringAsFixed(6)}..${fullMaxLat.toStringAsFixed(6)}]'
          '  lon:[${fullMinLon.toStringAsFixed(6)}..${fullMaxLon.toStringAsFixed(6)}]');
    print('   VP fracs → L=${leftFrac.toStringAsFixed(5)} R=${rightFrac.toStringAsFixed(5)}'
          ' B=${bottomFrac.toStringAsFixed(5)} T=${topFrac.toStringAsFixed(5)}');

    return {
      'min_lat': fullMinLat,
      'max_lat': fullMaxLat,
      'min_lon': fullMinLon,
      'max_lon': fullMaxLon,
    };
  }

  // ---------------------------------------------------------------------------

  /// Extract metadata dari PDF file.
  static Future<Map<String, dynamic>> extractMetadata(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        return {'success': false, 'error': 'PDF file not found: $pdfPath'};
      }
      final bytes = await file.readAsBytes();
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

  /// Extract geographic coordinates (neatline bounds) dari GeoPDF.
  ///
  /// Mengembalikan bounds GPTS yang merupakan area neatline/map-frame, bukan
  /// bounds halaman penuh. Gunakan [processGeoPdfAsOverlay] yang akan otomatis
  /// mengekspansi bounds ke full-page sebelum menyimpan ke Basemap.
  ///
  /// Key tambahan '_raw_content' disertakan di return value untuk dipakai
  /// oleh [processGeoPdfAsOverlay] tanpa harus membaca file ulang.
  static Future<Map<String, dynamic>> extractCoordinates(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        return {'success': false, 'error': 'PDF file not found'};
      }

      // Baca sebagai Latin-1 agar byte binary tidak dibuang
      final bytes = await file.readAsBytes();
      final content = String.fromCharCodes(bytes);

      Map<String, dynamic>? bounds;

      // ─── Pattern 1: GPTS 8-value ────────────────────────────────────────
      // Esri ArcMap / ArcGIS Pro: /GPTS[lat1 lon1 lat2 lon2 lat3 lon3 lat4 lon4]
      // Beberapa producer lain: [lon1 lat1 ...]
      // Deteksi otomatis berdasarkan range nilai.
      final gpts8 = RegExp(
        r'/GPTS\s*\[\s*([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)'
        r'\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s*\]',
      );

      final m8 = gpts8.firstMatch(content);
      if (m8 != null) {
        final raw = List.generate(8, (i) => double.parse(m8.group(i + 1)!));

        // Field pertama (index genap) vs kedua (index ganjil) tiap pasang
        final a = [raw[0], raw[2], raw[4], raw[6]];
        final b = [raw[1], raw[3], raw[5], raw[7]];

        final List<double> lats;
        final List<double> lons;

        final aOut = a.any((v) => v.abs() > 90);
        final bOut = b.any((v) => v.abs() > 90);

        if (aOut && !bOut) {
          lons = a; lats = b;
          print('📐 GPTS-8: lon-lat format (a out of lat range)');
        } else if (!aOut && bOut) {
          lats = a; lons = b;
          print('📐 GPTS-8: lat-lon format (b out of lat range)');
        } else {
          // Kedua dalam ±90: nilai abs lebih besar = longitude
          final avgA = a.map((v) => v.abs()).reduce((x, y) => x + y) / 4;
          final avgB = b.map((v) => v.abs()).reduce((x, y) => x + y) / 4;
          if (avgA > avgB) {
            lons = a; lats = b;
            print('📐 GPTS-8: lon-lat (heuristic avgA=$avgA > avgB=$avgB)');
          } else {
            lats = a; lons = b;
            print('📐 GPTS-8: lat-lon (heuristic avgB=$avgB >= avgA=$avgA)');
          }
        }

        bounds = {
          'min_lat': lats.reduce(math.min),
          'max_lat': lats.reduce(math.max),
          'min_lon': lons.reduce(math.min),
          'max_lon': lons.reduce(math.max),
        };
        print('✅ GPTS-8 neatline bounds: $bounds');
      }

      // ─── Pattern 2: BBox geografis ────────────────────────────────────────
      // PENTING: /VP BBox adalah koordinat halaman dalam pts (mis. 29..812),
      // BUKAN koordinat geografis. Filter hanya BBox dengan nilai dalam ±180.
      if (bounds == null) {
        final bboxPat = RegExp(
          r'/BBox\s*\[\s*([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s+([-.\d]+)\s*\]',
        );
        for (final bm in bboxPat.allMatches(content)) {
          final v = List.generate(4, (i) => double.parse(bm.group(i + 1)!));
          if (v.any((x) => x.abs() > 180)) {
            print('⏩ BBox skipped (bukan geo coords): $v');
            continue;
          }
          bounds = {
            'min_lat': math.min(v[1], v[3]),
            'max_lat': math.max(v[1], v[3]),
            'min_lon': math.min(v[0], v[2]),
            'max_lon': math.max(v[0], v[2]),
          };
          print('✅ BBox geo bounds: $bounds');
          break;
        }
      }

      // ─── Pattern 3: Measure/GPTS 4-value (format alternatif) ─────────────
      if (bounds == null) {
        final meas4 = RegExp(
          r'/Measure\s*<<.*?/GPTS\s*\[\s*([-.\d]+)\s+([-.\d]+)'
          r'\s+([-.\d]+)\s+([-.\d]+)\s*\]',
          dotAll: true,
        );
        final mm = meas4.firstMatch(content);
        if (mm != null) {
          final g = List.generate(4, (i) => double.parse(mm.group(i + 1)!));
          final isLonFirst = g[0].abs() > 90 || g[2].abs() > 90;
          bounds = isLonFirst
              ? {
                  'min_lat': math.min(g[1], g[3]),
                  'max_lat': math.max(g[1], g[3]),
                  'min_lon': math.min(g[0], g[2]),
                  'max_lon': math.max(g[0], g[2]),
                }
              : {
                  'min_lat': math.min(g[0], g[2]),
                  'max_lat': math.max(g[0], g[2]),
                  'min_lon': math.min(g[1], g[3]),
                  'max_lon': math.max(g[1], g[3]),
                };
          print('✅ Measure/GPTS-4 bounds: $bounds');
        }
      }

      if (bounds == null) {
        print('⚠️ No georeferencing data found in PDF');
        return {
          'success': false,
          'message': 'Tidak ada data georeferencing dalam PDF. '
              'Masukkan koordinat batas secara manual.',
        };
      }

      // ─── Validasi akhir: pastikan lat/lon tidak tertukar ──────────────────
      // (sebagai safety net untuk edge case GPTS yang tidak terdeteksi pattern-nya)
      var minLat = bounds['min_lat'] as double;
      var maxLat = bounds['max_lat'] as double;
      var minLon = bounds['min_lon'] as double;
      var maxLon = bounds['max_lon'] as double;

      bool needSwap = false;
      if (minLat.abs() > 90 || maxLat.abs() > 90) {
        needSwap = true;
        print('⚠️ Lat out of range → swapping');
      } else if (minLon.abs() <= 90 && maxLon.abs() <= 90) {
        final avgAbsLat = (minLat.abs() + maxLat.abs()) / 2;
        final avgAbsLon = (minLon.abs() + maxLon.abs()) / 2;
        if (avgAbsLat > avgAbsLon) {
          needSwap = true;
          print('⚠️ Lat magnitude > Lon magnitude → swapping');
        }
      }
      if (needSwap) {
        final tmpMin = minLat; final tmpMax = maxLat;
        bounds['min_lat'] = minLon; bounds['max_lat'] = maxLon;
        bounds['min_lon'] = tmpMin; bounds['max_lon'] = tmpMax;
        print('✅ After swap: $bounds');
      }

      print('✅ Final neatline coordinates: $bounds');
      return {
        'success': true,
        'bounds': bounds,
        // Raw content diteruskan ke processGeoPdfAsOverlay agar tidak baca file 2x
        '_raw_content': content,
      };
    } catch (e) {
      print('❌ extractCoordinates error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Convert PDF page ke image menggunakan native PDF renderer.
  static Future<Map<String, dynamic>> pdfToImage({
    required String pdfPath,
    required String outputPath,
    int page = 0,
    int? dpi,
  }) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        return {'success': false, 'error': 'PDF file not found'};
      }

      final pdfBytes  = await file.readAsBytes();
      final pageImages = await Printing.raster(
        pdfBytes,
        pages: [page],
        dpi: dpi?.toDouble() ?? 200.0,
      );

      final list = await pageImages.toList();
      if (list.isEmpty) {
        return {'success': false, 'error': 'Failed to render page $page'};
      }

      final pageImage = list.first;
      final pngBytes  = await pageImage.toPng();
      await File(outputPath).writeAsBytes(pngBytes);

      print('✅ PDF → image: ${pageImage.width}x${pageImage.height} @ ${dpi ?? 200} DPI');
      return {
        'success': true,
        'image_path': outputPath,
        'width':  pageImage.width,
        'height': pageImage.height,
        'dpi': dpi ?? 200,
      };
    } catch (e, st) {
      print('❌ pdfToImage error: $e\n$st');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Process GeoPDF sebagai overlay image (RECOMMENDED).
  ///
  /// Secara otomatis mengekspansi bounds dari neatline → full-page (Plan B)
  /// sehingga overlay image (render seluruh halaman) terpetakan dengan tepat
  /// tanpa pergeseran, meskipun PDF mempunyai margin, judul, atau legenda.
  ///
  /// Kompatibel dengan semua GeoPDF dari Esri ArcMap / ArcGIS Pro.
  static Future<Map<String, dynamic>> processGeoPdfAsOverlay({
    required String pdfPath,
    required String outputDir,
    int? dpi,
    Function(String)? onProgress,
    // Optional: override dengan koordinat manual (bypass auto-extract)
    double? manualMinLat,
    double? manualMinLon,
    double? manualMaxLat,
    double? manualMaxLon,
  }) async {
    try {
      final dir = Directory(outputDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      onProgress?.call('Extracting PDF metadata...');
      final metadata = await extractMetadata(pdfPath);
      if (metadata['success'] == false || metadata['success'] == null) {
        return metadata;
      }

      onProgress?.call('Extracting coordinates...');
      final coords = await extractCoordinates(pdfPath);

      Map<String, dynamic>? bounds;

      if (manualMinLat != null && manualMinLon != null &&
          manualMaxLat != null && manualMaxLon != null) {
        // Manual bounds: langsung pakai, tidak perlu expand
        print('📍 Using manual bounds (bypass auto-extract + expansion)');
        bounds = {
          'min_lat': manualMinLat,
          'min_lon': manualMinLon,
          'max_lat': manualMaxLat,
          'max_lon': manualMaxLon,
        };
      } else if (coords['success'] == true && coords['bounds'] != null) {
        final neatline = coords['bounds'] as Map<String, dynamic>;

        // ── Plan B: Ekspansi bounds neatline → full-page ──────────────────
        // overlay.png = render seluruh halaman PDF (termasuk margin, judul,
        // legenda, north arrow).  GPTS hanya mendefinisikan neatline (area
        // peta di dalam bingkai).  Tanpa koreksi ini, overlay bergeser sebesar
        // proporsi margin (~5% H, ~3.5% V pada PDF A4 ArcMap standar).
        //
        // Langkah:
        //   1. Baca MediaBox → ukuran halaman (pts)
        //   2. Baca VP/BBox  → posisi neatline (pts)
        //   3. Hitung fraksi viewport vs halaman
        //   4. Ekspansi linear GPTS bounds ke tepi halaman
        // ─────────────────────────────────────────────────────────────────
        final rawContent = coords['_raw_content'] as String?;
        bool expanded = false;

        if (rawContent != null) {
          final mediaBox = _extractMediaBox(rawContent);
          final vpBBox   = _extractViewportBBox(rawContent);

          if (mediaBox != null && vpBBox != null) {
            final pageW = mediaBox['width']!;
            final pageH = mediaBox['height']!;
            final vpW   = vpBBox['x_right']!  - vpBBox['x_left']!;
            final vpH   = vpBBox['y_top']!     - vpBBox['y_bottom']!;

            // Validasi: VP harus lebih kecil dari halaman dan berdimensi positif
            if (vpW > 0 && vpH > 0 && vpW < pageW && vpH < pageH) {
              bounds = _expandBoundsToFullPage(
                minLat:    neatline['min_lat'] as double,
                maxLat:    neatline['max_lat'] as double,
                minLon:    neatline['min_lon'] as double,
                maxLon:    neatline['max_lon'] as double,
                pageWidth:  pageW,
                pageHeight: pageH,
                vpXLeft:   vpBBox['x_left']!,
                vpXRight:  vpBBox['x_right']!,
                vpYBottom: vpBBox['y_bottom']!,
                vpYTop:    vpBBox['y_top']!,
              );
              expanded = true;
            } else {
              print('⚠️ VP BBox tidak valid '
                    '(vpW=$vpW vpH=$vpH pageW=$pageW pageH=$pageH) '
                    '→ pakai neatline bounds tanpa ekspansi');
            }
          } else {
            print('⚠️ MediaBox/VP tidak ditemukan '
                  '→ pakai neatline bounds tanpa ekspansi');
          }
        }

        if (!expanded) bounds = neatline;
      }

      if (bounds == null) {
        return {
          'success': false,
          'error': 'No georeferencing data found. Please provide coordinates manually.',
          'message': 'PDF ini tidak mengandung data georeferencing. '
              'Masukkan koordinat batas secara manual.',
        };
      }

      onProgress?.call(
        'Converting PDF to overlay image at ${dpi ?? 200} DPI (Mobile Optimized)...',
      );
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
        'image_width':  conversion['width'],
        'image_height': conversion['height'],
        'message': 'GeoPDF converted to overlay image '
            '(${conversion["width"]}x${conversion["height"]} '
            '@ ${dpi ?? 200} DPI - Mobile optimized)',
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

  /// Test GeoPDF service
  static Future<String> test() async {
    return '''
GeoPDF Processor (Native) is ready!
Functions:
  - extractMetadata
  - extractCoordinates  → returns neatline GPTS bounds + _raw_content
  - pdfToImage
  - processGeoPdfAsOverlay ⚡ RECOMMENDED
    → auto-expands bounds: neatline → full-page (Plan B, no shift)

No Python dependencies required!
''';
  }
}
