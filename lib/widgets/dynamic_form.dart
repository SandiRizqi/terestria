import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/form_field_model.dart';
import 'photo_field_widget.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class DynamicForm extends StatefulWidget {
  final List<FormFieldModel> formFields;
  final Function(Map<String, dynamic>) onSaved;
  final VoidCallback? onChanged;
  final Map<String, dynamic>? initialData; // Add initial data support

  const DynamicForm({
    Key? key,
    required this.formFields,
    required this.onSaved,
    this.onChanged,
    this.initialData,
  }) : super(key: key);

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  
  late Map<String, dynamic> _formData;
  final Map<String, TextEditingController> _textControllers = {};
  
  @override
  void initState() {
    super.initState();
    // Initialize formData with initialData if provided
    _formData = widget.initialData != null 
        ? Map<String, dynamic>.from(widget.initialData!) 
        : {};
  }
  
  @override
  void dispose() {
    // Clean up controllers
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _scanQRCode(FormFieldModel field) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => _QRScannerScreen(
          fieldLabel: field.label,
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      // Update text controller and form data
      _textControllers[field.label]?.text = result;
      _formData[field.label] = result;
      widget.onSaved(_formData);
      widget.onChanged?.call();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('QR Code scanned: $result'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Column(
      children: widget.formFields.map((field) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildFieldWidget(field),
        );
      }).toList(),
    );
  }

  Widget _buildFieldWidget(FormFieldModel field) {
    switch (field.type) {
      case FieldType.text:
        return _buildTextField(field);
      case FieldType.number:
        return _buildNumberField(field);
      case FieldType.date:
        return _buildDateField(field);
      case FieldType.dropdown:
        return _buildDropdownField(field);
      case FieldType.checkbox:
        return _buildCheckboxField(field);
      case FieldType.photo:
        return _buildPhotoField(field);
    }
  }

  Widget _buildTextField(FormFieldModel field) {
    // Create or reuse controller to preserve value
    if (!_textControllers.containsKey(field.label)) {
      // Use initialData if available
      final initialValue = _formData[field.label]?.toString() ?? '';
      _textControllers[field.label] = TextEditingController(
        text: initialValue,
      );
    }
    
    return TextFormField(
      controller: _textControllers[field.label],
      decoration: InputDecoration(
        labelText: field.label + (field.required ? ' *' : ''),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: 'Scan QR Code',
          onPressed: () => _scanQRCode(field),
        ),
      ),
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) {
          return 'This field is required';
        }
        return null;
      },
      onChanged: (value) {
        _formData[field.label] = value;
        widget.onSaved(_formData);
        widget.onChanged?.call();
      },
      onSaved: (value) {
        _formData[field.label] = value ?? '';
        widget.onSaved(_formData);
      },
    );
  }

  Widget _buildNumberField(FormFieldModel field) {
    // Create or reuse controller to preserve value
    if (!_textControllers.containsKey(field.label)) {
      // Use initialData if available
      final initialValue = _formData[field.label]?.toString() ?? '';
      _textControllers[field.label] = TextEditingController(
        text: initialValue,
      );
    }
    
    return TextFormField(
      controller: _textControllers[field.label],
      decoration: InputDecoration(
        labelText: field.label + (field.required ? ' *' : ''),
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) {
          return 'This field is required';
        }
        if (value != null && value.isNotEmpty) {
          if (double.tryParse(value) == null) {
            return 'Please enter a valid number';
          }
        }
        return null;
      },
      onChanged: (value) {
        _formData[field.label] = value != null && value.isNotEmpty
            ? double.tryParse(value) ?? value
            : '';
        widget.onSaved(_formData);
        widget.onChanged?.call();
      },
      onSaved: (value) {
        _formData[field.label] = value != null && value.isNotEmpty
            ? double.tryParse(value) ?? value
            : '';
        widget.onSaved(_formData);
      },
    );
  }

  Widget _buildDateField(FormFieldModel field) {
    // Parse initial date if exists
    DateTime? selectedDate;
    if (_formData[field.label] != null && _formData[field.label] is String) {
      try {
        selectedDate = DateTime.parse(_formData[field.label]);
      } catch (e) {
        selectedDate = null;
      }
    }

    return FormField<DateTime>(
      initialValue: selectedDate,
      validator: (value) {
        if (field.required && value == null) {
          return 'This field is required';
        }
        return null;
      },
      onSaved: (value) {
        _formData[field.label] = value?.toIso8601String() ?? '';
        widget.onSaved(_formData);
      },
      builder: (FormFieldState<DateTime> state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: selectedDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (date != null) {
                  state.didChange(date);
                  selectedDate = date;
                  _formData[field.label] = date.toIso8601String();
                  widget.onSaved(_formData);
                  widget.onChanged?.call();
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: field.label + (field.required ? ' *' : ''),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                  errorText: state.errorText,
                ),
                child: Text(
                  state.value != null
                      ? '${state.value!.day}/${state.value!.month}/${state.value!.year}'
                      : 'Select date',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDropdownField(FormFieldModel field) {
    // Get initial value
    final initialValue = _formData[field.label] as String?;
    
    return DropdownButtonFormField<String>(
      value: initialValue,
      decoration: InputDecoration(
        labelText: field.label + (field.required ? ' *' : ''),
        border: const OutlineInputBorder(),
      ),
      items: field.options?.map((option) {
        return DropdownMenuItem(
          value: option,
          child: Text(option),
        );
      }).toList(),
      validator: (value) {
        if (field.required && value == null) {
          return 'This field is required';
        }
        return null;
      },
      onSaved: (value) {
        _formData[field.label] = value ?? '';
        widget.onSaved(_formData);
      },
      onChanged: (value) {
        _formData[field.label] = value ?? '';
        widget.onSaved(_formData);
        widget.onChanged?.call();
      },
    );
  }

  Widget _buildCheckboxField(FormFieldModel field) {
    // Get initial value
    final initialValue = _formData[field.label] as bool? ?? false;

    return FormField<bool>(
      initialValue: initialValue,
      validator: (value) {
        if (field.required && value != true) {
          return 'This field is required';
        }
        return null;
      },
      onSaved: (value) {
        _formData[field.label] = value ?? false;
        widget.onSaved(_formData);
      },
      builder: (FormFieldState<bool> state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              title: Text(field.label + (field.required ? ' *' : '')),
              value: state.value,
              onChanged: (value) {
                state.didChange(value);
                // checkboxValue = value;
                _formData[field.label] = value ?? false;
                widget.onSaved(_formData);
                widget.onChanged?.call();
              },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(
                  state.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPhotoField(FormFieldModel field) {
    // Get initial photos - can be old format (List<String>) or new format (List<Map>)
    dynamic initialPhotos = _formData[field.label];
    
    final minPhotos = field.minPhotos ?? (field.required ? 1 : 0);
    final maxPhotos = field.maxPhotos ?? 1;

    return FormField<List<Map<String, dynamic>>>(
      initialValue: initialPhotos is List ? initialPhotos.cast<Map<String, dynamic>>() : [],
      validator: (value) {
        final photoCount = value?.length ?? 0;
        
        // Changed: Return null to not block form submission
        // Warning will be shown in UI but form can still be saved
        if (minPhotos > 0 && photoCount < minPhotos) {
          // Visual warning only, don't block
          return null;
        }
        
        if (photoCount > maxPhotos) {
          // This should still block as it's a hard limit
          return 'Maximum $maxPhotos photo${maxPhotos > 1 ? "s" : ""} allowed';
        }
        
        return null;
      },
      onSaved: (value) {
        _formData[field.label] = value ?? [];
        widget.onSaved(_formData);
      },
      builder: (FormFieldState<List<Map<String, dynamic>>> state) {
        return PhotoFieldWidget(
          label: field.label,
          required: field.required,
          minPhotos: minPhotos,
          maxPhotos: maxPhotos,
          initialPhotos: initialPhotos,
          errorText: state.errorText,
          onChanged: (photos) {
            state.didChange(photos);
            _formData[field.label] = photos;
            widget.onSaved(_formData);
            widget.onChanged?.call();
          },
        );
      },
    );
  }
}

// QR Scanner Screen Widget
class _QRScannerScreen extends StatefulWidget {
  final String fieldLabel;

  const _QRScannerScreen({required this.fieldLabel});

  @override
  State<_QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<_QRScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  bool _isProcessing = false;
  bool _isTorchOn = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final String? code = barcode.rawValue;

    if (code != null && code.isNotEmpty) {
      setState(() => _isProcessing = true);
      
      // Vibrate or play sound (optional)
      HapticFeedback.mediumImpact();
      
      // Return the scanned code
      Navigator.pop(context, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan QR for "${widget.fieldLabel}"'),
        actions: [
          IconButton(
            icon: Icon(
              _isTorchOn ? Icons.flash_on : Icons.flash_off,
              color: _isTorchOn ? Colors.yellow : null,
            ),
            onPressed: () async {
              await cameraController.toggleTorch();
              setState(() {
                _isTorchOn = !_isTorchOn;
              });
            },
            tooltip: 'Toggle Flashlight',
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => cameraController.switchCamera(),
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: cameraController,
            onDetect: _onDetect,
          ),
          
          // Overlay with scanning frame
          CustomPaint(
            painter: _ScannerOverlayPainter(),
            child: Container(),
          ),
          
          // Instructions
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Position the QR code within the frame',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for scanner overlay
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double scanAreaSize = size.width * 0.7;
    final double left = (size.width - scanAreaSize) / 2;
    final double top = (size.height - scanAreaSize) / 2;
    final Rect scanArea = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    // Draw semi-transparent overlay
    final Paint backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Draw overlay with hole for scan area
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(scanArea, const Radius.circular(12))),
      ),
      backgroundPaint,
    );

    // Draw corner brackets
    final Paint cornerPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    const double cornerLength = 30;
    
    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLength)
        ..lineTo(left, top)
        ..lineTo(left + cornerLength, top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(left + scanAreaSize - cornerLength, top)
        ..lineTo(left + scanAreaSize, top)
        ..lineTo(left + scanAreaSize, top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, top + scanAreaSize - cornerLength)
        ..lineTo(left, top + scanAreaSize)
        ..lineTo(left + cornerLength, top + scanAreaSize),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(left + scanAreaSize - cornerLength, top + scanAreaSize)
        ..lineTo(left + scanAreaSize, top + scanAreaSize)
        ..lineTo(left + scanAreaSize, top + scanAreaSize - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
