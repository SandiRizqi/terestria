import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

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

  const PhotoFieldWidget({
    Key? key,
    required this.label,
    required this.required,
    required this.minPhotos,
    required this.maxPhotos,
    this.initialPhotos,
    this.errorText,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<PhotoFieldWidget> createState() => _PhotoFieldWidgetState();
}

class _PhotoFieldWidgetState extends State<PhotoFieldWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  
  final ImagePicker _picker = ImagePicker();
  List<PhotoData> _photos = [];

  @override
  void initState() {
    super.initState();
    _initializePhotos();
  }

  void _initializePhotos() {
    if (widget.initialPhotos != null) {
      if (widget.initialPhotos is List) {
        final list = widget.initialPhotos as List;
        _photos = [];
        for (var item in list) {
          if (item is Map) {
            // PhotoData format
            try {
              _photos.add(PhotoData.fromJson(Map<String, dynamic>.from(item)));
            } catch (e) {
              print('Error parsing PhotoData: $e');
            }
          } else if (item is String && item.isNotEmpty) {
            // Old string format - convert to PhotoData
            _photos.add(PhotoData.fromPath(item));
          }
        }
      }
    }
  }

  Future<void> _takePhoto() async {
    if (_photos.length >= widget.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum ${widget.maxPhotos} photo(s) allowed')),
      );
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        final photoData = PhotoData.fromPath(photo.path);
        setState(() {
          _photos.add(photoData);
        });
        widget.onChanged(_photos.map((p) => p.toJson()).toList());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error taking photo: $e')),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_photos.length >= widget.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum ${widget.maxPhotos} photo(s) allowed')),
      );
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        final photoData = PhotoData.fromPath(image.path);
        setState(() {
          _photos.add(photoData);
        });
        widget.onChanged(_photos.map((p) => p.toJson()).toList());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking photo: $e')),
        );
      }
    }
  }

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

  @override
  void didUpdateWidget(PhotoFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update photos if initialPhotos changed
    if (widget.initialPhotos != oldWidget.initialPhotos) {
      _initializePhotos();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    // Check if photo count meets requirements
    final photoCount = _photos.length;
    final hasError = widget.errorText != null;
    final hasWarning = widget.minPhotos > 0 && photoCount < widget.minPhotos;
    final isExceedingMax = photoCount > widget.maxPhotos;
    
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
                      ? (hasError ? Theme.of(context).colorScheme.error : Colors.orange[800])
                      : null,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasError
                    ? Theme.of(context).colorScheme.error.withOpacity(0.1)
                    : hasWarning
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasError
                      ? Theme.of(context).colorScheme.error.withOpacity(0.3)
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
        if (_photos.length < widget.maxPhotos)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFromGallery,
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
              '${photoCount}/${widget.maxPhotos} photo(s)',
              style: TextStyle(
                fontSize: 12,
                color: hasError
                    ? Theme.of(context).colorScheme.error
                    : hasWarning
                        ? Colors.orange[800]
                        : Colors.grey[600],
                fontWeight: hasError || hasWarning ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (widget.minPhotos > 0 && photoCount < widget.minPhotos)
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
        
        // Warning message for insufficient photos  
        if (hasWarning) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.orange.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.orange[800],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.minPhotos == 1
                        ? 'At least 1 photo is recommended'
                        : 'At least ${widget.minPhotos} photos are recommended',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[900],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        
        // Error message for exceeding max
        if (hasError && widget.errorText != null) ...[
      ],
    ]);
  }
}

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
