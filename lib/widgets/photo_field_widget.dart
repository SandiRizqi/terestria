import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:geoform_app/config/api_config.dart';
import 'package:geoform_app/services/crashlytics_service.dart';
import 'package:geoform_app/services/settings_service.dart';

import '../models/geo_data_model.dart';
import '../services/device_health_service.dart';
import '../utils/app_logger.dart';
import '../utils/ui_feedback.dart';

/// Data untuk encode JPEG di isolate (lihat [_encodeJpegRgba]).
class _JpegJob {
  final int width;
  final int height;
  final Uint8List rgba;
  final int quality;
  const _JpegJob(this.width, this.height, this.rgba, this.quality);
}

/// Encode piksel RGBA → JPEG. Top-level agar bisa dijalankan via `compute`
/// (encode 1920×1080 memakan ratusan ms — jangan di thread UI).
Uint8List _encodeJpegRgba(_JpegJob job) {
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    bytesOffset: job.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: job.quality);
}

/// Photo metadata for form data
class PhotoData {
  final String name;
  final String localPath;
  final String? serverUrl;
  final String? serverKey; // OSS key for stable reference
  final DateTime created;
  final DateTime updated;

  PhotoData({
    required this.name,
    required this.localPath,
    this.serverUrl,
    this.serverKey,
    required this.created,
    required this.updated,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'localPath': localPath,
      'serverUrl': serverUrl,
      'serverKey': serverKey,
      'created': created.toIso8601String(),
      'updated': updated.toIso8601String(),
    };
  }

  factory PhotoData.fromJson(Map<String, dynamic> json) {
    return PhotoData(
      name: json['name'],
      localPath: json['localPath'],
      serverUrl: json['serverUrl'],
      serverKey: json['serverKey'],
      created: DateTime.parse(json['created']),
      updated: DateTime.parse(json['updated']),
    );
  }

  // For backward compatibility: create from string path
  factory PhotoData.fromPath(String path) {
    final file = File(path);
    final filename = file.path.split('/').last;
    return PhotoData(
      name: filename,
      localPath: path,
      serverUrl: null,
      serverKey: null,
      created: DateTime.now(),
      updated: DateTime.now(),
    );
  }
}

class PhotoFieldWidget extends StatefulWidget {
  final String label;
  final bool required;
  final int minPhotos;
  final int maxPhotos;
  final dynamic initialPhotos; // Can be List<String> or List<Map>
  final String? errorText;
  final Function(List<Map<String, dynamic>>) onChanged; // Now returns PhotoData as JSON

  // Watermark info — passed from DataCollectionScreen via DynamicForm
  final String? username;
  final double? latitude;
  final double? longitude;

  /// Posisi terkini saat shutter ditekan (diutamakan untuk watermark).
  final GeoPoint? Function()? locationProvider;

  // ── Static flag so DataCollectionScreen knows not to restart streams ──
  // while the camera is open (P2 fix)
  static bool isCameraActive = false;

  const PhotoFieldWidget({
    Key? key,
    required this.label,
    required this.required,
    required this.minPhotos,
    required this.maxPhotos,
    this.initialPhotos,
    this.errorText,
    required this.onChanged,
    this.username,
    this.latitude,
    this.longitude,
    this.locationProvider,
  }) : super(key: key);

  @override
  State<PhotoFieldWidget> createState() => _PhotoFieldWidgetState();
}

class _PhotoFieldWidgetState extends State<PhotoFieldWidget>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  final ImagePicker _picker = ImagePicker();
  List<PhotoData> _photos = [];

  // P2: flag for lifecycle gating
  bool _isCameraOpen = false;

  // Watermark: device ID loaded once from SharedPreferences
  String? _deviceId;

  // Watermark: Terestria logo decoded once and cached across instances.
  static ui.Image? _cachedLogo;

  /// Load (and cache) the transparent Terestria logo for the watermark.
  Future<ui.Image?> _loadLogo() async {
    if (_cachedLogo != null) return _cachedLogo;
    try {
      final data = await rootBundle
          .load('assets/terestria_logo_square-removebg-preview.png');
      final codec =
          await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cachedLogo = frame.image;
      return _cachedLogo;
    } catch (e) {
      logWarn('⚠️ Watermark: failed to load logo: $e', tag: 'PHOTO');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializePhotos();
    WidgetsBinding.instance.addObserver(this); // for retrieveLostData
    _loadDeviceId();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// P2 + Bug #2: detect app resume after camera was open
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isCameraOpen) {
      // Camera was open when we went background – try to recover the photo
      // in case Android killed our Activity (Bug #2)
      _isCameraOpen = false;
      PhotoFieldWidget.isCameraActive = false;
      _recoverLostPhoto();
    }
  }

  @override
  void didUpdateWidget(PhotoFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPhotos != oldWidget.initialPhotos) {
      _initializePhotos();
      setState(() {});
    }
  }

  // ─────────────────────────────────────────────────────────
  // Init helpers
  // ─────────────────────────────────────────────────────────

  void _initializePhotos() {
    if (widget.initialPhotos != null) {
      if (widget.initialPhotos is List) {
        final list = widget.initialPhotos as List;
        _photos = [];
        for (var item in list) {
          if (item is Map) {
            try {
              _photos.add(PhotoData.fromJson(Map<String, dynamic>.from(item)));
            } catch (e) {
              logWarn('Error parsing PhotoData: $e', tag: 'PHOTO');
            }
          } else if (item is String && item.isNotEmpty) {
            _photos.add(PhotoData.fromPath(item));
          }
        }
      }
    }
  }

  Future<void> _loadDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _deviceId = prefs.getString('device_id') ?? 'N/A';
        });
      }
    } catch (e) {
      logWarn('⚠️ Could not load device ID: $e', tag: 'PHOTO');
      _deviceId = 'N/A';
    }
  }

  // ─────────────────────────────────────────────────────────
  // Bug #2: Recover photo after Android Activity Recreation
  // ─────────────────────────────────────────────────────────

  Future<void> _recoverLostPhoto() async {
    try {
      if (!mounted) return;

      logDebug('🔄 Checking for lost photo data (Activity recreation)...', tag: 'PHOTO');
      final LostDataResponse response = await _picker.retrieveLostData();

      if (!mounted) return;
      if (response.isEmpty) {
        logDebug('ℹ️ No lost photo data found', tag: 'PHOTO');
        return;
      }

      if (response.file != null) {
        logDebug('📸 Lost photo recovered! Processing...', tag: 'PHOTO');
        final persistentPath = await _processAndSavePhoto(response.file!.path);

        if (!mounted) return; // P1: mounted check after heavy async

        final photoData = PhotoData.fromPath(persistentPath);
        setState(() {
          _photos.add(photoData);
        });
        widget.onChanged(_photos.map((p) => p.toJson()).toList());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📸 Photo recovered'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        logDebug('✅ Lost photo recovered and saved', tag: 'PHOTO');
      } else if (response.exception != null) {
        logWarn('⚠️ Lost data had an exception: ${response.exception}', tag: 'PHOTO');
      }
    } catch (e) {
      logError('❌ Error recovering lost photo: $e', tag: 'PHOTO');
    }
  }

  // ─────────────────────────────────────────────────────────
  // P4: Persistent storage with retry + validation
  // ─────────────────────────────────────────────────────────

  /// Validate source exists, then apply watermark + copy to persistent storage.
  /// Retries up to [maxRetries] times on failure.
  Future<String> _processAndSavePhoto(String tempPath,
      {int maxRetries = 2}) async {
    // P4: Validate temp file still exists
    final tempFile = File(tempPath);
    if (!await tempFile.exists()) {
      throw Exception('Source photo file not found: $tempPath');
    }

    int attempt = 0;
    while (true) {
      try {
        return await _applyWatermarkAndSave(tempPath);
      } catch (e) {
        attempt++;
        if (attempt > maxRetries) {
          logError('❌ Photo save failed after $maxRetries retries: $e', tag: 'PHOTO');
          rethrow;
        }
        logWarn('⚠️ Photo save attempt $attempt failed – retrying in ${300 * attempt}ms: $e', tag: 'PHOTO');
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // Watermark rendering (dart:ui canvas)
  // ─────────────────────────────────────────────────────────

  Future<String> _applyWatermarkAndSave(String tempPath) async {
    // Prepare destination
    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${appDir.path}/photos/originals');
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Tanpa watermark: salin file kamera apa adanya (JPEG ±300–600 KB, EXIF
    // utuh). Dulu selalu di-encode ulang ke PNG (±5–10× lebih besar) sehingga
    // upload di sinyal lemah terus timeout.
    if (!SettingsService().settings.photoWatermark) {
      final dot = tempPath.lastIndexOf('.');
      final ext = dot >= 0 && tempPath.length - dot <= 5
          ? tempPath.substring(dot).toLowerCase()
          : '.jpg';
      final copied =
          await File(tempPath).copy('${photoDir.path}/IMG_$timestamp$ext');
      logDebug('✅ Photo saved: ${copied.path}', tag: 'PHOTO');
      return copied.path;
    }

    final newPath = '${photoDir.path}/IMG_$timestamp.jpg';
    // Posisi saat shutter ditekan (bukan saat form dibuka).
    final loc = widget.locationProvider?.call();
    final latitude = loc?.latitude ?? widget.latitude;
    final longitude = loc?.longitude ?? widget.longitude;

    // Decode source image
    final bytes = await File(tempPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final original = frame.image;

    try {
      final w = original.width.toDouble();
      final h = original.height.toDouble();

      // Canvas setup
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, w, h),
      );

      // Draw original image
      canvas.drawImage(original, Offset.zero, Paint());

      // Watermark (diaktifkan di Settings) — jalur tanpa watermark sudah
      // kembali lebih awal dengan menyalin file asli.
      {
      // ─────────────────────────────────────────────────────────
      // Premium watermark card (bottom-left) with Terestria logo
      // ─────────────────────────────────────────────────────────
      final now     = DateTime.now();
      final dateStr = DateFormat('dd MMM yyyy').format(now);
      final timeStr = DateFormat('HH:mm:ss').format(now);

      String fmtLat(double? v) => v == null
          ? 'N/A'
          : '${v >= 0 ? 'N' : 'S'} ${v.abs().toStringAsFixed(6)}°';
      String fmtLng(double? v) => v == null
          ? 'N/A'
          : '${v >= 0 ? 'E' : 'W'} ${v.abs().toStringAsFixed(6)}°';

      // Scale everything relative to the photo's width so the card looks
      // consistent on any resolution.
      final unit      = (w * 0.0125).clamp(9.0, 26.0);
      final pad       = unit * 1.25;
      final brandSize = unit * 1.55;
      final subSize   = unit * 0.82;
      final metaSize  = unit * 1.02;
      final lineH     = metaSize * 1.62;
      final logoSize  = brandSize + subSize + unit * 0.6;
      final accentH   = (unit * 0.16).clamp(2.0, 6.0);
      final radius    = unit * 0.9;

      final logo = await _loadLogo();

      // Card metrics
      const metaCount = 4;
      final cardW  = (w * 0.52).clamp(240.0, w - unit * 2);
      final cardH  = pad + logoSize + unit * 0.7 + accentH + unit * 0.7 +
          metaCount * lineH + pad * 0.55;
      final cardX  = unit;
      final cardY  = h - cardH - unit;
      final cardRect = Rect.fromLTWH(cardX, cardY, cardW, cardH);
      final rrect  = RRect.fromRectAndRadius(cardRect, Radius.circular(radius));

      // Helper to draw a line of text.
      void drawText(
        String s,
        double x,
        double y,
        double size,
        Color color, {
        FontWeight weight = FontWeight.w600,
        double? maxWidth,
      }) {
        final pb = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textDirection: ui.TextDirection.ltr,
            textAlign: ui.TextAlign.left,
            maxLines: 1,
            ellipsis: '…',
          ),
        )
          ..pushStyle(ui.TextStyle(
            color: color,
            fontSize: size,
            fontWeight: weight,
            letterSpacing: 0.2,
            shadows: const [
              ui.Shadow(
                color: Color(0x99000000),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ))
          ..addText(s);
        final p = pb.build()
          ..layout(ui.ParagraphConstraints(width: maxWidth ?? (cardW - pad * 2)));
        canvas.drawParagraph(p, Offset(x, y));
      }

      // Soft drop shadow behind the card.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cardRect.translate(0, unit * 0.15),
          Radius.circular(radius),
        ),
        Paint()
          ..color = const Color(0x55000000)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
      );

      // Card background — dark gradient for a premium glassy look.
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(cardX, cardY),
            Offset(cardX, cardY + cardH),
            const [Color(0xF00C2014), Color(0xE0081109)],
          ),
      );
      // Subtle hairline border.
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.06
          ..color = const Color(0x33FFFFFF),
      );
      // Left accent bar (brand green).
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        Rect.fromLTWH(cardX, cardY, unit * 0.34, cardH),
        Paint()..color = const Color(0xFF019A3E),
      );
      canvas.restore();

      final cx = cardX + pad;
      double cy = cardY + pad * 0.85;

      // Header: logo + brand text.
      if (logo != null) {
        canvas.drawImageRect(
          logo,
          Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
          Rect.fromLTWH(cx, cy, logoSize, logoSize),
          Paint()..filterQuality = FilterQuality.high,
        );
      }
      final textX = cx + (logo != null ? logoSize + pad * 0.7 : 0);
      drawText('TERESTRIA', textX, cy + logoSize * 0.06, brandSize,
          const Color(0xFFFFFFFF),
          weight: FontWeight.w800, maxWidth: cardW - (textX - cardX) - pad);
      drawText('Geospatial Survey  •  v${ApiConfig.appVersion}', textX,
          cy + logoSize * 0.06 + brandSize * 1.18, subSize,
          const Color(0xFF8FE3A8),
          weight: FontWeight.w500, maxWidth: cardW - (textX - cardX) - pad);

      cy += logoSize + unit * 0.7;

      // Accent divider.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx, cy, cardW - pad * 2, accentH),
          Radius.circular(accentH / 2),
        ),
        Paint()..color = const Color(0x33FFFFFF),
      );
      cy += accentH + unit * 0.7;

      // Metadata rows: label (green) + value (white).
      final rows = <List<String>>[
        ['Lat', fmtLat(latitude)],
        ['Lng', fmtLng(longitude)],
        ['Time', '$dateStr  $timeStr'],
        ['Surveyor',
            '${widget.username ?? 'Unknown'}   ·   ID ${_deviceId ?? 'N/A'}'],
      ];
      final labelW = unit * 4.6;
      for (final r in rows) {
        drawText(r[0], cx, cy, metaSize, const Color(0xFF8FE3A8),
            weight: FontWeight.w700, maxWidth: labelW);
        drawText(r[1], cx + labelW, cy, metaSize, const Color(0xFFFFFFFF),
            weight: FontWeight.w600, maxWidth: cardW - pad * 2 - labelW);
        cy += lineH;
      }
      } // end watermark

      // ── Render & export ──
      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(
        original.width,
        original.height,
      );

      try {
        final byteData =
            await finalImage.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (byteData == null) {
          throw StateError('Could not read watermarked image pixels');
        }
        // JPEG (bukan PNG) & encode di isolate agar UI tak tersendat.
        final jpeg = await compute(
          _encodeJpegRgba,
          _JpegJob(finalImage.width, finalImage.height,
              byteData.buffer.asUint8List(), 88),
        );
        await File(newPath).writeAsBytes(jpeg, flush: true);
        logDebug('✅ Photo saved with watermark: $newPath '
            '(${(jpeg.length / 1024).round()} KB)', tag: 'PHOTO');
        return newPath;
      } finally {
        finalImage.dispose();
      }
    } finally {
      original.dispose();
    }
  }

  // ─────────────────────────────────────────────────────────
  // P1 + P2: Take photo with all fixes
  // ─────────────────────────────────────────────────────────

  Future<void> _takePhoto() async {
    if (_photos.length >= widget.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Maximum ${widget.maxPhotos} photo(s) allowed')),
      );
      return;
    }

    // Penyimpanan hampir penuh → foto bisa gagal disimpan; tanya dulu.
    if (!await confirmStorageFor(context, action: 'Taking photos')) return;
    if (!mounted) return;

    try {
      // P2: Set flags BEFORE opening camera
      _isCameraOpen = true;
      PhotoFieldWidget.isCameraActive = true;

      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      // P2: Reset flag immediately after camera returns
      _isCameraOpen = false;
      PhotoFieldWidget.isCameraActive = false;

      // P1: mounted check after first async gap
      if (!mounted) return;

      if (photo != null) {
        // P4: Validate temp file exists (guard against Activity recreation)
        final tempFile = File(photo.path);
        if (!await tempFile.exists()) {
          logWarn(
              '⚠️ Camera temp file missing – photo may arrive via retrieveLostData', tag: 'PHOTO');
          return;
        }

        // P1: mounted check after file IO
        if (!mounted) return;

        final persistentPath = await _processAndSavePhoto(photo.path);

        // P1: mounted check after heavy processing
        if (!mounted) return;

        final photoData = PhotoData.fromPath(persistentPath);
        setState(() {
          _photos.add(photoData);
        });
        widget.onChanged(_photos.map((p) => p.toJson()).toList());
      }
    } catch (e, stack) {
      // P2: Always reset flags on error
      _isCameraOpen = false;
      PhotoFieldWidget.isCameraActive = false;

      crashlytics.setContext('photo_source', 'camera');
      crashlytics.setContext('photo_field_label', widget.label);
      crashlytics.recordError(e, stack, reason: 'Photo: takePhoto failed');

      if (mounted) {
        showErrorFeedback(context, 'Could not take the photo',
            error: e, stack: stack, tag: 'PHOTO', log: false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // P1 + P2: Pick from gallery with all fixes
  // ─────────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    if (_photos.length >= widget.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Maximum ${widget.maxPhotos} photo(s) allowed')),
      );
      return;
    }

    // Penyimpanan hampir penuh → foto bisa gagal disimpan; tanya dulu.
    if (!await confirmStorageFor(context, action: 'Adding photos')) return;
    if (!mounted) return;

    try {
      // P2: flag for gallery too (gallery picker can also cause lifecycle changes)
      _isCameraOpen = true;
      PhotoFieldWidget.isCameraActive = true;

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      _isCameraOpen = false;
      PhotoFieldWidget.isCameraActive = false;

      // P1: mounted check after async gap
      if (!mounted) return;

      if (image != null) {
        // P4: Validate source file
        final srcFile = File(image.path);
        if (!await srcFile.exists()) {
          logWarn('⚠️ Gallery source file missing', tag: 'PHOTO');
          return;
        }

        // P1: mounted check after file IO
        if (!mounted) return;

        final persistentPath = await _processAndSavePhoto(image.path);

        // P1: mounted check after processing
        if (!mounted) return;

        final photoData = PhotoData.fromPath(persistentPath);
        setState(() {
          _photos.add(photoData);
        });
        widget.onChanged(_photos.map((p) => p.toJson()).toList());
      }
    } catch (e, stack) {
      _isCameraOpen = false;
      PhotoFieldWidget.isCameraActive = false;

      crashlytics.setContext('photo_source', 'gallery');
      crashlytics.setContext('photo_field_label', widget.label);
      crashlytics.recordError(e, stack, reason: 'Photo: pickFromGallery failed');

      if (mounted) {
        showErrorFeedback(context, 'Could not add the photo',
            error: e, stack: stack, tag: 'PHOTO', log: false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // Other actions
  // ─────────────────────────────────────────────────────────

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
    });
    widget.onChanged(_photos.map((p) => p.toJson()).toList());
  }

  void _viewPhoto(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoViewScreen(imagePath: path),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final photoCount = _photos.length;
    final hasError = widget.errorText != null;
    final hasWarning = widget.minPhotos > 0 && photoCount < widget.minPhotos;

    final minRequirement = widget.minPhotos > 0
        ? '${widget.minPhotos}${widget.minPhotos < widget.maxPhotos ? '-${widget.maxPhotos}' : ''}'
        : 'up to ${widget.maxPhotos}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${widget.label}${widget.required ? ' *' : ''}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: hasError || hasWarning
                          ? (hasError
                              ? Theme.of(context).colorScheme.error
                              : Colors.orange[800])
                          : null,
                    ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasError
                    ? Theme.of(context)
                        .colorScheme
                        .error
                        .withOpacity(0.1)
                    : hasWarning
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasError
                      ? Theme.of(context)
                          .colorScheme
                          .error
                          .withOpacity(0.3)
                      : hasWarning
                          ? Colors.orange.withOpacity(0.4)
                          : Colors.blue.withOpacity(0.3),
                ),
              ),
              child: Text(
                minRequirement,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hasError
                      ? Theme.of(context).colorScheme.error
                      : hasWarning
                          ? Colors.orange[800]
                          : Colors.blue[700],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Photo Grid
        if (_photos.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photo = _photos[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  InkWell(
                    onTap: () => _viewPhoto(photo.localPath),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(photo.localPath),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            const Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () => _removePhoto(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

        if (_photos.isNotEmpty) const SizedBox(height: 8),

        // Add Photo Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _photos.length < widget.maxPhotos
                    ? _takePhoto
                    : null,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _photos.length < widget.maxPhotos
                    ? _pickFromGallery
                    : null,
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$photoCount/${widget.maxPhotos} photo(s)',
              style: TextStyle(
                fontSize: 12,
                color: hasError
                    ? Theme.of(context).colorScheme.error
                    : hasWarning
                        ? Colors.orange[800]
                        : Colors.grey[600],
                fontWeight: hasError || hasWarning
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            if (widget.minPhotos > 0 &&
                photoCount < widget.minPhotos)
              Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    size: 14,
                    color: Colors.orange[700],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Need ${widget.minPhotos - photoCount} more',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),

        // Max reached
        if (photoCount >= widget.maxPhotos) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.green.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 16, color: Colors.green[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Maximum photos reached',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[900],
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ]
        // Below minimum
        else if (hasWarning) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.orange.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.orange[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.minPhotos == 1
                        ? 'At least 1 photo is recommended'
                        : 'At least ${widget.minPhotos} photos are recommended',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[900],
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen photo viewer
// ─────────────────────────────────────────────────────────────────────────────

class PhotoViewScreen extends StatelessWidget {
  final String imagePath;

  const PhotoViewScreen({Key? key, required this.imagePath}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.file(File(imagePath)),
        ),
      ),
    );
  }
}
