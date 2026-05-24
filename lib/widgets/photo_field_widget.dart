import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:geoform_app/config/api_config.dart';
import 'package:geoform_app/services/crashlytics_service.dart';

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
              print('Error parsing PhotoData: $e');
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
      print('⚠️ Could not load device ID: $e');
      _deviceId = 'N/A';
    }
  }

  // ─────────────────────────────────────────────────────────
  // Bug #2: Recover photo after Android Activity Recreation
  // ─────────────────────────────────────────────────────────

  Future<void> _recoverLostPhoto() async {
    try {
      if (!mounted) return;

      print('🔄 Checking for lost photo data (Activity recreation)...');
      final LostDataResponse response = await _picker.retrieveLostData();

      if (!mounted) return;
      if (response.isEmpty) {
        print('ℹ️ No lost photo data found');
        return;
      }

      if (response.file != null) {
        print('📸 Lost photo recovered! Processing...');
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
              content: Text('📸 Foto berhasil dipulihkan'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        print('✅ Lost photo recovered and saved');
      } else if (response.exception != null) {
        print('⚠️ Lost data had an exception: ${response.exception}');
      }
    } catch (e) {
      print('❌ Error recovering lost photo: $e');
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
          print('❌ Photo save failed after $maxRetries retries: $e');
          rethrow;
        }
        print('⚠️ Photo save attempt $attempt failed – retrying in ${300 * attempt}ms: $e');
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
    final newPath = '${photoDir.path}/IMG_$timestamp.png';

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

      // ── Watermark text lines ──
      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);

      final latStr = widget.latitude != null
          ? widget.latitude!.toStringAsFixed(6)
          : 'N/A';
      final lngStr = widget.longitude != null
          ? widget.longitude!.toStringAsFixed(6)
          : 'N/A';

      final lines = [
        'Terestria v${ApiConfig.appVersion}',
        'User: ${widget.username ?? 'Unknown'}',
        'Lat: $latStr',
        'Lng: $lngStr',
        'ID: ${_deviceId ?? 'N/A'}',
        dateStr,
      ];

      // ── Layout calculations (relative to image size) ──
      final fontSize = (w * 0.022).clamp(12.0, 30.0);
      final lineSpacing = fontSize * 1.55;
      final pad = fontSize * 0.9;
      final boxH = lines.length * lineSpacing + pad * 2;
      final boxW = w * 0.50;
      final startX = pad;
      final startY = h - boxH - pad;

      // ── Background rounded rect ──
      final bgPaint = Paint()..color = const Color(0xD2000000);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(startX, startY, boxW, boxH),
          Radius.circular(pad * 0.5),
        ),
        bgPaint,
      );

      // ── Draw each text line ──
      for (int i = 0; i < lines.length; i++) {
        final pb = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textDirection: ui.TextDirection.ltr,
            textAlign: ui.TextAlign.left,
          ),
        )
          ..pushStyle(ui.TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: fontSize,
            fontWeight: ui.FontWeight.w700,
            shadows: const [
              ui.Shadow(
                color: Color(0xAA000000),
                offset: Offset(1, 1),
                blurRadius: 3,
              ),
            ],
          ))
          ..addText(lines[i]);

        final para = pb.build();
        para.layout(ui.ParagraphConstraints(width: boxW - pad * 1.5));

        canvas.drawParagraph(
          para,
          Offset(startX + pad, startY + pad + i * lineSpacing),
        );
      }

      // ── Render & export ──
      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(
        original.width,
        original.height,
      );

      try {
        final byteData =
            await finalImage.toByteData(format: ui.ImageByteFormat.png);
        await File(newPath)
            .writeAsBytes(byteData!.buffer.asUint8List());
        print('✅ Photo with watermark saved: $newPath');
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
          print(
              '⚠️ Camera temp file missing – photo may arrive via retrieveLostData');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error taking photo: $e')),
        );
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
          print('⚠️ Gallery source file missing');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking photo: $e')),
        );
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
