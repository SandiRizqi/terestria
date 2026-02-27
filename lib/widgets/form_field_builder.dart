import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/form_field_model.dart';
import '../theme/app_theme.dart';

class FormFieldBuilderDialog extends StatefulWidget {
  final FormFieldModel? field;
  final List<FormFieldModel>? existingFields; // untuk cek field photo yang sudah ada

  const FormFieldBuilderDialog({
    Key? key, 
    this.field,
    this.existingFields,
  }) : super(key: key);

  @override
  State<FormFieldBuilderDialog> createState() => _FormFieldBuilderDialogState();
}

class _FormFieldBuilderDialogState extends State<FormFieldBuilderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _optionsController = TextEditingController();
  final _uuid = const Uuid();

  FieldType _selectedType = FieldType.text;
  bool _isRequired = false;
  int _minPhotos = 0;
  int _maxPhotos = 1;

  @override
  void initState() {
    super.initState();
    if (widget.field != null) {
      _labelController.text = widget.field!.label;
      _selectedType = widget.field!.type;
      _isRequired = widget.field!.required;
      _minPhotos = widget.field!.minPhotos ?? 0;
      _maxPhotos = widget.field!.maxPhotos ?? 1;
      if (widget.field!.options != null) {
        _optionsController.text = widget.field!.options!.join('\n');
      }
    } else {
      // Untuk field baru, jika type photo maka set label default
      if (_selectedType == FieldType.photo) {
        _labelController.text = 'Photo';
      }
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    List<String>? options;
    if (_selectedType == FieldType.dropdown) {
      options = _optionsController.text
          .split('\n')
          .where((s) => s.trim().isNotEmpty)
          .toList();
      
      if (options.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dropdown must have at least one option')),
        );
        return;
      }
    }

    final field = FormFieldModel(
      id: widget.field?.id ?? _uuid.v4(),
      label: _labelController.text,
      type: _selectedType,
      required: _isRequired,
      options: options,
      minPhotos: _selectedType == FieldType.photo ? _minPhotos : null,
      maxPhotos: _selectedType == FieldType.photo ? _maxPhotos : null,
    );

    Navigator.pop(context, field);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.field == null ? 'Add Form Field' : 'Edit Form Field'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Label
              TextFormField(
                controller: _labelController,
                enabled: _selectedType != FieldType.photo, // Disable untuk photo field
                decoration: InputDecoration(
                  labelText: 'Field Label',
                  border: const OutlineInputBorder(),
                  filled: _selectedType == FieldType.photo,
                  fillColor: _selectedType == FieldType.photo ? Colors.grey[100] : null,
                  helperText: _selectedType == FieldType.photo ? 'Photo field label is fixed to "Photo"' : null,
                  helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a label';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppTheme.spacingMedium),

              // Field Type
              DropdownButtonFormField<FieldType>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Field Type',
                  border: OutlineInputBorder(),
                ),
                items: FieldType.values.map((type) {
                  String displayName;
                  bool isDisabled = false;
                  
                  if (type == FieldType.photo) {
                    displayName = 'Photo';
                    // Disable photo option jika sudah ada photo field dan ini bukan edit field photo
                    if (widget.existingFields != null) {
                      final hasPhotoField = widget.existingFields!.any((f) => 
                        f.type == FieldType.photo && f.id != widget.field?.id
                      );
                      isDisabled = hasPhotoField;
                    }
                  } else {
                    displayName = type.toString().split('.').last;
                    displayName = displayName[0].toUpperCase() + displayName.substring(1);
                  }
                  
                  return DropdownMenuItem(
                    value: type,
                    enabled: !isDisabled,
                    child: Row(
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            color: isDisabled ? Colors.grey : null,
                          ),
                        ),
                        if (isDisabled) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.lock,
                            size: 16,
                            color: Colors.grey[400],
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                    // Auto set label ke "Photo" jika photo type dipilih
                    if (_selectedType == FieldType.photo) {
                      _labelController.text = 'Photo';
                    }
                  });
                },
              ),
              const SizedBox(height: AppTheme.spacingMedium),

              // Options (only for dropdown)
              if (_selectedType == FieldType.dropdown) ...[
                TextFormField(
                  controller: _optionsController,
                  decoration: const InputDecoration(
                    labelText: 'Options (one per line)',
                    border: OutlineInputBorder(),
                    hintText: 'Option 1\nOption 2\nOption 3',
                  ),
                  maxLines: 5,
                  validator: (value) {
                    if (_selectedType == FieldType.dropdown &&
                        (value == null || value.isEmpty)) {
                      return 'Please enter at least one option';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.spacingMedium),
              ],

              // Min/Max Photos (only for photo field)
              if (_selectedType == FieldType.photo) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.photo_library, size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'Photo Requirements',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Minimum Photos: $_minPhotos',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Slider(
                        value: _minPhotos.toDouble(),
                        min: 0,
                        max: _maxPhotos.toDouble(),
                        divisions: _maxPhotos,
                        label: _minPhotos == 0 ? 'Optional' : _minPhotos.toString(),
                        onChanged: (value) {
                          setState(() => _minPhotos = value.toInt());
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Maximum Photos: $_maxPhotos',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Slider(
                        value: _maxPhotos.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: _maxPhotos.toString(),
                        onChanged: (value) {
                          final newMax = value.toInt();
                          setState(() {
                            _maxPhotos = newMax;
                            // Ensure min doesn't exceed max
                            if (_minPhotos > newMax) {
                              _minPhotos = newMax;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _minPhotos == 0
                                    ? 'Photos are optional (0-$_maxPhotos)'
                                    : _minPhotos == _maxPhotos
                                        ? 'Exactly $_minPhotos photo${_minPhotos > 1 ? "s" : ""} required'
                                        : 'Required: $_minPhotos-$_maxPhotos photos',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMedium),
              ],

              // Required checkbox
              CheckboxListTile(
                title: const Text('Required Field'),
                value: _isRequired,
                onChanged: (value) {
                  setState(() => _isRequired = value ?? false);
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
