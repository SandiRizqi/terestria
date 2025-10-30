import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class PhotoFieldWidget extends StatefulWidget {
  final String label;
  final bool required;
  final int minPhotos;
  final int maxPhotos;
  final List<String>? initialPhotos;
  final String? errorText;
  final Function(List<String>) onChanged;

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
  List<String> _photoPaths = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPhotos != null) {
      _photoPaths = List.from(widget.initialPhotos!);
    }
  }

  Future<void> _takePhoto() async {
    if (_photoPaths.length >= widget.maxPhotos) {
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
        setState(() {
          _photoPaths.add(photo.path);
        });
        widget.onChanged(_photoPaths);
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
    if (_photoPaths.length >= widget.maxPhotos) {
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
        setState(() {
          _photoPaths.add(image.path);
        });
        widget.onChanged(_photoPaths);
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
      _photoPaths.removeAt(index);
    });
    widget.onChanged(_photoPaths);
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
    if (widget.initialPhotos != oldWidget.initialPhotos && 
        widget.initialPhotos != null && 
        widget.initialPhotos != _photoPaths) {
      setState(() {
        _photoPaths = List.from(widget.initialPhotos!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    // Check if photo count meets requirements
    final photoCount = _photoPaths.length;
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
        if (_photoPaths.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _photoPaths.length,
            itemBuilder: (context, index) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  InkWell(
                    onTap: () => _viewPhoto(_photoPaths[index]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_photoPaths[index]),
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
        
        if (_photoPaths.isNotEmpty) const SizedBox(height: 8),
        
        // Add Photo Buttons
        if (_photoPaths.length < widget.maxPhotos)
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
